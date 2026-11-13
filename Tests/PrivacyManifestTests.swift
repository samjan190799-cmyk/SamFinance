import XCTest
@testable import SamFinance

/// Apple проверяет каждый манифест приватности внутри приложения, в том числе из SDK, уже после отправки на проверку:
/// нарушение ставит версии статус «Ошибка двоичного файла» (ITMS-91064, TN3181). Здесь те же правила проверяются
/// на собранном приложении, пока сборка ещё не ушла в App Store Connect.
final class PrivacyManifestTests: XCTestCase {
    private struct FoundManifest {
        let path: String
        let tracking: Any?
        let domains: Any?
    }

    /// Все файлы PrivacyInfo.xcprivacy в приложении: свой, из фреймворков и из ресурсных пакетов SDK
    private func allManifests() throws -> [FoundManifest] {
        let root = Bundle(for: FinanceService.self).bundleURL
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var found = [FoundManifest]()
        for case let url as URL in walker where url.lastPathComponent == "PrivacyInfo.xcprivacy" {
            let relative = url.path.hasPrefix(root.path + "/") ? String(url.path.dropFirst(root.path.count + 1)) : url.path
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let dictionary = try XCTUnwrap(object as? [String: Any], "\(relative): манифест не словарь")
            found.append(FoundManifest(path: relative, tracking: dictionary["NSPrivacyTracking"], domains: dictionary["NSPrivacyTrackingDomains"]))
        }
        return found
    }

    func testEveryPrivacyManifestInTheAppFollowsAppleTrackingRules() throws {
        let manifests = try allManifests()
        XCTAssertTrue(
            manifests.contains { $0.path == "PrivacyInfo.xcprivacy" },
            "манифест самого приложения не найден среди: \(manifests.map(\.path))"
        )

        for manifest in manifests {
            let isTracking = (manifest.tracking as? Bool) == true
            var domains = [String]()
            if let raw = manifest.domains {
                let list = raw as? [String]
                XCTAssertNotNil(list, "\(manifest.path): NSPrivacyTrackingDomains должен быть массивом строк")
                domains = list ?? []
            }

            if isTracking {
                XCTAssertFalse(domains.isEmpty, "\(manifest.path): NSPrivacyTracking = true, а список доменов пуст (ITMS-91064)")
            } else {
                XCTAssertTrue(domains.isEmpty, "\(manifest.path): есть домены отслеживания, а NSPrivacyTracking не true (ITMS-91064): \(domains)")
            }
            for domain in domains {
                XCTAssertNotNil(
                    domain.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression),
                    "\(manifest.path): домен «\(domain)» должен быть без схемы, пути и слеша"
                )
            }
        }
    }
}
