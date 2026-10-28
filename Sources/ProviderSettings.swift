import Foundation
import Security
import LocalAuthentication

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
        static let codexModel = "codexModel"
        static let defaultProvider = "defaultSummaryProvider"
        static let hasCompletedOnboarding = "hasCompletedProviderOnboarding"
        static let claudeWorkspaceID = "claudeWorkspaceID"
        static let claudeWorkspaceName = "claudeWorkspaceName"
        static let claudeNeedsWorkspaceID = "claudeNeedsWorkspaceID"
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

    var codexModel: String? { defaults.string(forKey: DefaultsKey.codexModel) }

    static func validatedCodexModel(_ value: String) throws -> String? {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/:-")
        guard model.utf8.count <= 160, model.first != "-",
              model.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AppError.message("Enter a model ID without spaces, or leave it blank to use Codex's default.")
        }
        return model
    }

    func saveCodexModel(_ value: String) throws {
        if let model = try Self.validatedCodexModel(value) {
            defaults.set(model, forKey: DefaultsKey.codexModel)
        } else {
            defaults.removeObject(forKey: DefaultsKey.codexModel)
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: DefaultsKey.hasCompletedOnboarding) }
    }

    func hasClaudeAPIKey() throws -> Bool {
        var query = baseKeychainQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context

        switch SecItemCopyMatching(query as CFDictionary, nil) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw AppError.message("Claude Keychain status is unavailable. Try again after unlocking your Mac.")
        }
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

    var claudeWorkspaceID: String? {
        defaults.string(forKey: DefaultsKey.claudeWorkspaceID)
    }

    var claudeWorkspaceName: String? {
        defaults.string(forKey: DefaultsKey.claudeWorkspaceName)
    }

    var claudeNeedsWorkspaceID: Bool {
        get { defaults.bool(forKey: DefaultsKey.claudeNeedsWorkspaceID) }
        set { defaults.set(newValue, forKey: DefaultsKey.claudeNeedsWorkspaceID) }
    }

    func saveClaudeAPIKey(_ key: String, workspaceID: String = "") throws {
        let value = try Self.validatedClaudeAPIKey(key)
        let workspace = try Self.validatedClaudeWorkspaceID(workspaceID)

        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseKeychainQuery as CFDictionary, update as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            break
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
        defaults.set(workspace, forKey: DefaultsKey.claudeWorkspaceID)
        defaults.removeObject(forKey: DefaultsKey.claudeWorkspaceName)
        claudeNeedsWorkspaceID = false
    }

    func saveClaudeWorkspaceID(_ workspaceID: String, name: String? = nil) throws {
        let workspace = try Self.validatedClaudeWorkspaceID(workspaceID)
        guard try hasClaudeAPIKey() else {
            throw AppError.message("Save a Claude API key before setting its workspace.")
        }
        let selectedName = name ?? (workspace == claudeWorkspaceID ? claudeWorkspaceName : nil)
        defaults.set(workspace, forKey: DefaultsKey.claudeWorkspaceID)
        defaults.set(selectedName, forKey: DefaultsKey.claudeWorkspaceName)
    }

    static func validatedClaudeAPIKey(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw AppError.message("Paste a Claude API key to continue.")
        }
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw AppError.message("The key contains spaces or line breaks. Paste only the API key.")
        }
        guard value.hasPrefix("sk-ant-"), value.count >= 24,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw AppError.message("This does not look like a complete Claude API key. Paste only the full key beginning sk-ant-.")
        }
        return value
    }

    static func validatedClaudeWorkspaceID(_ input: String) throws -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.hasPrefix("wrkspc_"), value.count > 7,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 95 }) else {
            throw AppError.message("The workspace ID should begin wrkspc_. Copy its ID from Claude Console, not its name.")
        }
        return value
    }

    func deleteClaudeAPIKey() throws {
        let status = SecItemDelete(baseKeychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("Claude’s API key could not be removed from Keychain. Check your Mac’s Keychain access and try again.")
        }
        defaults.removeObject(forKey: DefaultsKey.claudeWorkspaceID)
        defaults.removeObject(forKey: DefaultsKey.claudeWorkspaceName)
        defaults.removeObject(forKey: DefaultsKey.claudeNeedsWorkspaceID)
    }

    private var baseKeychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}

enum ClaudeKeyVerificationError: LocalizedError {
    case workspaceRequired

    var errorDescription: String? {
        switch self {
        case .workspaceRequired:
            "This key works across workspaces. Choose where Note Ferry should run, then paste its workspace ID below."
        }
    }
}

enum ClaudeKeyVerificationResult: Equatable {
    case connected
    case defaultWorkspace(String)
}

final class ClaudeKeyVerifier {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    func verify(_ key: String, workspaceID: String? = nil, completion: @escaping (Result<ClaudeKeyVerificationResult, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(ClaudeRunner.modelID)")!)
        request.httpMethod = "GET"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        if let workspaceID { request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id") }
        session.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(AppError.message("Could not reach Anthropic. Check your connection and try again; the key remains saved.")))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(AppError.message("Anthropic did not return a response. Try again; the key remains saved.")))
                return
            }
            switch response.statusCode {
            case 200:
                completion(.success(.connected))
            case 401:
                completion(.failure(AppError.message("Anthropic rejected this key. Check that you copied the full API key, or create a new one.")))
            case 403:
                completion(.failure(AppError.message("Anthropic recognized the key but denied access. Check its workspace and permissions in Claude Console.")))
            case 404 where workspaceID == nil:
                completion(.failure(AppError.message("Claude Sonnet 4.6 is not available to this key. Check its model access in Claude Console.")))
            case 400 where Self.workspaceIDError(in: data):
                if workspaceID == nil {
                    self.resolveDefaultWorkspace(for: key, completion: completion)
                } else {
                    completion(.failure(ClaudeKeyVerificationError.workspaceRequired))
                }
            case 404 where workspaceID != nil:
                completion(.failure(ClaudeKeyVerificationError.workspaceRequired))
            default:
                completion(.failure(AppError.message("Anthropic could not verify the key (HTTP \(response.statusCode)). Try again later; the key remains saved.")))
            }
        }.resume()
    }

    private func resolveDefaultWorkspace(
        for key: String,
        completion: @escaping (Result<ClaudeKeyVerificationResult, Error>) -> Void
    ) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/organizations/workspaces?include_default=true&limit=100")!)
        request.httpMethod = "GET"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let response = response as? HTTPURLResponse,
                  response.statusCode == 200, let data,
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let workspaces = body["data"] as? [[String: Any]],
                  let defaultWorkspace = workspaces.first(where: {
                      ($0["name"] as? String)?.caseInsensitiveCompare("Default") == .orderedSame
                          && ($0["archived_at"] == nil || $0["archived_at"] is NSNull)
                  }),
                  let id = defaultWorkspace["id"] as? String,
                  (try? ProviderSettings.validatedClaudeWorkspaceID(id)) != nil else {
                completion(.failure(ClaudeKeyVerificationError.workspaceRequired))
                return
            }
            self.verify(key, workspaceID: id) { result in
                switch result {
                case .success:
                    completion(.success(.defaultWorkspace(id)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    static func workspaceIDError(in data: Data?) -> Bool {
        guard let data,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = body["error"] as? [String: Any],
              let message = error["message"] as? String else { return false }
        return message.contains("anthropic-workspace-id")
    }
}
