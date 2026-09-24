import Foundation
import Security

enum SummaryProvider: String, CaseIterable {
    case apple
    case codex
    case claude

    var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var shortDescription: String {
        switch self {
        case .apple: "Summarize on this Mac with Apple Intelligence."
        case .codex: "Use your signed-in Codex account."
        case .claude: "Use your Claude API key."
        }
    }
}

final class ProviderSettings {
    static let shared = ProviderSettings()

    private enum DefaultsKey {
        static let defaultProvider = "defaultSummaryProvider"
        static let hasCompletedOnboarding = "hasCompletedProviderOnboarding"
    }

    private let defaults: UserDefaults
    private let keychainService: String
    private let keychainAccount = "claude-api-key"

    init(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "me.nieder.summary-notes"
    ) {
        self.defaults = defaults
        self.keychainService = "\(bundleIdentifier).claude-api-key"
    }

    var defaultProvider: SummaryProvider {
        get {
            guard let value = defaults.string(forKey: DefaultsKey.defaultProvider),
                  let provider = SummaryProvider(rawValue: value) else {
                return .apple
            }
            return provider
        }
        set {
            defaults.set(newValue.rawValue, forKey: DefaultsKey.defaultProvider)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: DefaultsKey.hasCompletedOnboarding) }
    }

    func loadClaudeAPIKey() throws -> String? {
        var query = baseKeychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw AppError.message("Claude’s saved API key could not be read. Save it again in Settings.")
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw AppError.message("Claude’s API key could not be read from Keychain. Check your Mac’s Keychain access and try again.")
        }
    }

    func saveClaudeAPIKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw AppError.message("Enter a Claude API key before saving.")
        }

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseKeychainQuery as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseKeychainQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AppError.message("Claude’s API key could not be saved to Keychain. Check your Mac’s Keychain access and try again.")
            }
        default:
            throw AppError.message("Claude’s API key could not be saved to Keychain. Check your Mac’s Keychain access and try again.")
        }
    }

    func deleteClaudeAPIKey() throws {
        let status = SecItemDelete(baseKeychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("Claude’s API key could not be removed from Keychain. Check your Mac’s Keychain access and try again.")
        }
    }

    private var baseKeychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
