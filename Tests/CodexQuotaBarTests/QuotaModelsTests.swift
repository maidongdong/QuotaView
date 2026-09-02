import XCTest
@testable import CodexQuotaBar

final class QuotaModelsTests: XCTestCase {
    func testSelectsWeeklyWindowFromNewSingleWindowResponse() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 29,
              "windowDurationMins": 10080,
              "resetsAt": 1781179384
            },
            "secondary": null
          }
        }
        """

        let result = try JSONDecoder().decode(
            RateLimitsResult.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(result.rateLimits.fiveHour)
        XCTAssertEqual(result.rateLimits.weekly?.remainingPercent, 71)
    }

    func testSelectsBothWindowsFromCurrentResponse() throws {
        let json = """
        {
          "primary": {
            "usedPercent": 6,
            "windowDurationMins": 300,
            "resetsAt": 1781179384
          },
          "secondary": {
            "usedPercent": 1,
            "windowDurationMins": 10080,
            "resetsAt": 1781748128
          }
        }
        """

        let snapshot = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 94)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 99)
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(
            RateLimitWindow(
                usedPercent: 140,
                windowDurationMins: 300,
                resetsAt: nil
            ).remainingPercent,
            0
        )
        XCTAssertEqual(
            RateLimitWindow(
                usedPercent: -10,
                windowDurationMins: 300,
                resetsAt: nil
            ).remainingPercent,
            100
        )
    }

    func testDisplayStateSuccessDoesNotExposeSourceCopy() throws {
        let json = """
        {
          "primary": {
            "usedPercent": 20,
            "windowDurationMins": 300,
            "resetsAt": 1781179384
          },
          "secondary": {
            "usedPercent": 30,
            "windowDurationMins": 10080,
            "resetsAt": 1781748128
          }
        }
        """

        let snapshot = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(json.utf8)
        )
        let state = QuotaDisplayState(snapshot: snapshot)

        XCTAssertEqual(state.status, "已更新")
        XCTAssertEqual(state.fiveHour?.remainingPercent, 80)
        XCTAssertEqual(state.weekly?.remainingPercent, 70)
        XCTAssertFalse(state.status.contains("app-server"))
    }

    func testPendingDisplayStateCarriesVisibleStatus() {
        let state = QuotaDisplayState.pending("账号已切换，正在刷新额度…")

        XCTAssertNil(state.fiveHour)
        XCTAssertNil(state.weekly)
        XCTAssertNil(state.updatedAt)
        XCTAssertEqual(state.status, "账号已切换，正在刷新额度…")
    }

    func testDetectsSuspiciousZeroUsageInSameResetWindow() throws {
        let previous = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(
                """
                {
                  "primary": {
                    "usedPercent": 29,
                    "windowDurationMins": 300,
                    "resetsAt": 1781179384
                  },
                  "secondary": {
                    "usedPercent": 17,
                    "windowDurationMins": 10080,
                    "resetsAt": 1781748128
                  }
                }
                """.utf8
            )
        )
        let current = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(
                """
                {
                  "primary": {
                    "usedPercent": 0,
                    "windowDurationMins": 300,
                    "resetsAt": 1781179384
                  },
                  "secondary": {
                    "usedPercent": 17,
                    "windowDurationMins": 10080,
                    "resetsAt": 1781748128
                  }
                }
                """.utf8
            )
        )

        XCTAssertTrue(current.hasSuspiciousZeroUsage(comparedTo: previous))
    }

    func testAllowsZeroUsageAfterResetWindowChanges() throws {
        let previous = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(
                """
                {
                  "primary": {
                    "usedPercent": 29,
                    "windowDurationMins": 300,
                    "resetsAt": 1781179384
                  },
                  "secondary": {
                    "usedPercent": 17,
                    "windowDurationMins": 10080,
                    "resetsAt": 1781748128
                  }
                }
                """.utf8
            )
        )
        let current = try JSONDecoder().decode(
            RateLimitSnapshot.self,
            from: Data(
                """
                {
                  "primary": {
                    "usedPercent": 0,
                    "windowDurationMins": 300,
                    "resetsAt": 1781190000
                  },
                  "secondary": {
                    "usedPercent": 17,
                    "windowDurationMins": 10080,
                    "resetsAt": 1781748128
                  }
                }
                """.utf8
            )
        )

        XCTAssertFalse(current.hasSuspiciousZeroUsage(comparedTo: previous))
    }
}
