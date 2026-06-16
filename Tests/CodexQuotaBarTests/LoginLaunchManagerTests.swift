import Foundation
import XCTest
@testable import CodexQuotaBar

final class LoginLaunchManagerTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "LoginLaunchManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFirstEligibleLaunchDefaultsEnabledAndRegisters() {
        let service = FakeLoginLaunchService(status: .notRegistered)
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: true
        )

        manager.synchronizeOnLaunch()

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(
            manager.state,
            LoginLaunchState(desiredEnabled: true, systemState: .enabled)
        )
    }

    func testUserDisablingPersistsAcrossManagerInstances() {
        let service = FakeLoginLaunchService(status: .enabled)
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: true
        )

        manager.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(
            manager.state,
            LoginLaunchState(desiredEnabled: false, systemState: .disabled)
        )

        let nextService = FakeLoginLaunchService(status: .notRegistered)
        let nextManager = LoginLaunchManager(
            service: nextService,
            defaults: defaults,
            installationIsEligible: true
        )
        nextManager.synchronizeOnLaunch()

        XCTAssertEqual(nextService.registerCallCount, 0)
        XCTAssertEqual(
            nextManager.state,
            LoginLaunchState(desiredEnabled: false, systemState: .disabled)
        )
    }

    func testIneligibleInstallationKeepsDefaultCheckedWithoutRegistering() {
        let service = FakeLoginLaunchService(status: .notRegistered)
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: false
        )

        manager.synchronizeOnLaunch()

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(
            manager.state,
            LoginLaunchState(desiredEnabled: true, systemState: .installRequired)
        )
    }

    func testRequiresApprovalKeepsDesiredStateChecked() {
        let service = FakeLoginLaunchService(status: .requiresApproval)
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: true
        )

        manager.refresh()

        XCTAssertEqual(
            manager.state,
            LoginLaunchState(desiredEnabled: true, systemState: .requiresApproval)
        )
    }

    func testWritableAppsOutsideApplicationsAreEligible() {
        XCTAssertTrue(
            LoginLaunchManager.isEligibleInstallation(
                at: URL(fileURLWithPath: "/Applications/CodexQuotaBar.app")
            )
        )
        XCTAssertTrue(
            LoginLaunchManager.isEligibleInstallation(
                at: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications/CodexQuotaBar.app")
            )
        )
        XCTAssertTrue(
            LoginLaunchManager.isEligibleInstallation(
                at: URL(fileURLWithPath: "/private/tmp/CodexQuotaBar.app")
            )
        )
        XCTAssertFalse(
            LoginLaunchManager.isEligibleInstallation(
                at: URL(fileURLWithPath: "/Volumes/Codex 额度栏/CodexQuotaBar.app")
            )
        )
    }

    func testRegisterFailureKeepsCheckboxDesiredOnAndShowsFailure() {
        let service = FakeLoginLaunchService(
            status: .notRegistered,
            registerError: TestError.registrationFailed
        )
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: true
        )

        manager.synchronizeOnLaunch()

        XCTAssertTrue(manager.state.desiredEnabled)
        guard case .failed = manager.state.systemState else {
            return XCTFail("Expected registration failure state")
        }
    }

    func testManualEnablingUpdatesDesiredStateBeforeRegistrationFinishes() {
        defaults.set(false, forKey: LoginLaunchManager.desiredEnabledKey)
        let service = FakeLoginLaunchService(
            status: .notRegistered,
            registerError: TestError.registrationFailed
        )
        let manager = LoginLaunchManager(
            service: service,
            defaults: defaults,
            installationIsEligible: true
        )

        manager.setEnabled(true)

        XCTAssertTrue(manager.state.desiredEnabled)
        XCTAssertTrue(defaults.bool(forKey: LoginLaunchManager.desiredEnabledKey))
    }
}

private final class FakeLoginLaunchService: LoginLaunchServicing {
    var status: LoginLaunchServiceStatus
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private let registerError: Error?

    init(status: LoginLaunchServiceStatus, registerError: Error? = nil) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

private enum TestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "registration failed"
    }
}
