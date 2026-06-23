import Foundation

struct CodexAccountService {
    func readAccount(client: CodexAppServerClient, completion: @escaping @Sendable (Result<CodexAccount, Error>) -> Void) {
        client.sendRequest(method: "account/read", params: ["refreshToken": false]) { result in
            switch result {
            case .success(let response):
                do {
                    completion(.success(try parseAccountResponse(response)))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseAccountResponse(_ response: CodexAppServerClient.JSONDictionary) throws -> CodexAccount {
        guard let result = response["result"] as? CodexAppServerClient.JSONDictionary else {
            throw QuotaError.parsingFailed(I18n.current.missingAccountResult)
        }

        let account = result["account"] as? CodexAppServerClient.JSONDictionary
        return CodexAccount(
            type: account?["type"] as? String,
            email: account?["email"] as? String,
            planType: account?["planType"] as? String,
            requiresOpenaiAuth: result["requiresOpenaiAuth"] as? Bool ?? false
        )
    }
}
