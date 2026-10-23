//
//  APIKey.swift
//  Easydict
//
//  Created by tisfeng on 2024/2/15.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import Foundation

// MARK: - APIKey

extension BuiltInAIService {
    var builtInAIAPIKey: String {
        APIKey.builtInAIAPIKey.stringValue
    }

    var builtInAIEndpoint: String {
        APIKey.builtInAIEndpoint.stringValue
    }
}

extension CaiyunService {
    var caiyunToken: String {
        APIKey.caiyunToken.stringValue
    }
}

extension NiuTransService {
    @objc var niutransAPIKey: String {
        APIKey.niutransAPIKey.stringValue
    }
}

// MARK: - APIKey

enum APIKey: String {
    /**
     For convenience, we provide a default key for users to try out the service.
     Please do not abuse it, otherwise it may be revoked.
     */

    case openAIAPIKey
    case openAIEndpoint
    case geminiAPIKey
    case caiyunToken
    case niutransAPIKey
    case builtInAIAPIKey
    case builtInAIEndpoint
    case builtInAIModel

    // MARK: Internal

    var stringValue: String {
        SecretKeyManager.keyValues[rawValue] ?? ""
    }
}

// MARK: - SecretKeyManager

@objcMembers
class SecretKeyManager: NSObject {
    // MARK: Internal

    /// Decrypted built-in key values, loaded lazily on first access.
    ///
    /// The bundled plist never changes at runtime, so it is read and decrypted once
    /// instead of on every access. `static let` initialization is thread-safe.
    static let keyValues: [String: String] = loadKeyValues()

    // MARK: Private

    private static func loadKeyValues() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "EncryptedSecretKeys", ofType: "plist") else {
            return [:]
        }

        guard let dict = NSDictionary(contentsOfFile: path) else {
            return [:]
        }

        var decryptedKeyValues = [String: String]()
        for (key, value) in dict {
            if let key = key as? String, let value = value as? String {
                decryptedKeyValues[key] = value.decryptAES()
            }
        }

        return decryptedKeyValues
    }
}
