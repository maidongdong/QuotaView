import Foundation
import ServiceManagement

enum LoginLaunchServiceStatus {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

protocol LoginLaunchServicing {
    var status: LoginLaunchServiceStatus { get }
    func register() throws
    func unregister() throws
}

private struct MainAppLoginLaunchService: LoginLaunchServicing {
    private let service = SMAppService.mainApp

    var status: LoginLaunchServiceStatus {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}

enum LoginLaunchSystemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case installRequired
    case failed(String)
}

struct LoginLaunchState: Equatable {
    let desiredEnabled: Bool
    let systemState: LoginLaunchSystemState
}

final class LoginLaunchManager {
    static let desiredEnabledKey = "loginLaunch.desiredEnabled"

    var onStateChange: ((LoginLaunchState) -> Void)?
    private(set) var state: LoginLaunchState

    private let service: LoginLaunchServicing
    private let defaults: UserDefaults
    private let installationIsEligible: Bool
    private var desiredEnabled: Bool

    convenience init() {
        self.init(
            service: MainAppLoginLaunchService(),
            defaults: .standard,
            installationIsEligible: Self.isEligibleInstallation(at: Bundle.main.bundleURL)
        )
    }

    init(
        service: LoginLaunchServicing,
        defaults: UserDefaults,
        installationIsEligible: Bool
    ) {
        self.service = service
        self.defaults = defaults
        self.installationIsEligible = installationIsEligible
        desiredEnabled = defaults.object(forKey: Self.desiredEnabledKey) as? Bool ?? true
        state = LoginLaunchState(
            desiredEnabled: desiredEnabled,
            systemState: installationIsEligible
                ? Self.systemState(for: service.status)
                : .installRequired
        )
    }

    func synchronizeOnLaunch() {
        reconcileDesiredState()
    }

    func setEnabled(_ enabled: Bool) {
        desiredEnabled = enabled
        defaults.set(enabled, forKey: Self.desiredEnabledKey)
        publish(systemState: state.systemState)
        reconcileDesiredState()
    }

    func refresh() {
        guard installationIsEligible else {
            publish(systemState: .installRequired)
            return
        }
        publish(systemState: Self.systemState(for: service.status))
    }

    private func reconcileDesiredState() {
        guard installationIsEligible else {
            publish(systemState: .installRequired)
            return
        }

        do {
            if desiredEnabled {
                switch service.status {
                case .enabled, .requiresApproval:
                    break
                case .notRegistered, .notFound:
                    try service.register()
                }
            } else {
                switch service.status {
                case .notRegistered, .notFound:
                    break
                case .enabled, .requiresApproval:
                    try service.unregister()
                }
            }
            refresh()
        } catch {
            let action = desiredEnabled ? "开启" : "关闭"
            publish(systemState: .failed("\(action)失败：\(error.localizedDescription)"))
        }
    }

    private func publish(systemState: LoginLaunchSystemState) {
        let newState = LoginLaunchState(
            desiredEnabled: desiredEnabled,
            systemState: systemState
        )
        state = newState
        onStateChange?(newState)
    }

    private static func systemState(
        for status: LoginLaunchServiceStatus
    ) -> LoginLaunchSystemState {
        switch status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        }
    }

    static func isEligibleInstallation(at bundleURL: URL) -> Bool {
        guard bundleURL.pathExtension.lowercased() == "app" else {
            return false
        }

        let path = bundleURL.standardizedFileURL.path
        guard !path.hasPrefix("/Volumes/") else {
            return false
        }

        let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly != true
    }
}
