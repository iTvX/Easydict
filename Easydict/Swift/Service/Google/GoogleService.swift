//
//  GoogleService.swift
//  Easydict
//
//  Created by tisfeng on 2025/11/27.
//  Copyright © 2025 izual. All rights reserved.
//

import AFNetworking
import Defaults
import Foundation
import JavaScriptCore

private let kGoogleTranslateURL = "https://translate.google.com"

// MARK: - GoogleService

@objc(EZGoogleService)
class GoogleService: QueryService {
    // MARK: Open

    /// Returns configuration items for Google service settings.
    /// Google TTS mode and credentials are configured from Advanced settings.
    open override func configurationListItems() -> Any? {
        nil
    }

    // MARK: - JavaScript Context

    lazy var jsContext: JSContext = {
        let context = JSContext()
        if let jsPath = Bundle.main.path(forResource: "google-translate-sign", ofType: "js"),
           let jsString = try? String(contentsOfFile: jsPath, encoding: .utf8) {
            context?.evaluateScript(jsString)
        }
        return context!
    }()

    lazy var signFunction: JSValue = {
        jsContext.objectForKeyedSubscript("sign")
    }()

    lazy var windowObject: JSValue = {
        jsContext.objectForKeyedSubscript("window")
    }()

    // MARK: - HTTP Session Managers

    lazy var htmlSession: AFHTTPSessionManager = {
        let session = AFHTTPSessionManager()

        let requestSerializer = AFHTTPRequestSerializer()
        requestSerializer.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        session.requestSerializer = requestSerializer

        let responseSerializer = AFHTTPResponseSerializer()
        responseSerializer.acceptableContentTypes = ["text/html"]
        session.responseSerializer = responseSerializer

        return session
    }()

    lazy var jsonSession: AFHTTPSessionManager = {
        let session = AFHTTPSessionManager()

        let requestSerializer = AFHTTPRequestSerializer()
        requestSerializer.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.120 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        session.requestSerializer = requestSerializer

        let responseSerializer = AFJSONResponseSerializer()
        responseSerializer.acceptableContentTypes = ["application/json"]
        session.responseSerializer = responseSerializer

        return session
    }()

    // MARK: - QueryService Override

    /// Translate text using Google web or GTX APIs.
    override func translate(
        _ text: String,
        from: Language,
        to: Language
    ) async throws
        -> QueryResult {
        let processedText = maxTextLength(text, fromLanguage: from)

        // TODO: We should the Google web translate API instead.
        // Two APIs are hard to maintain, and they may differ with web translation.
        let queryDictionary = processedText.shouldQueryDictionary(
            withLanguage: from,
            maxWordCount: 1
        )

        return try await withCheckedThrowingContinuation { continuation in
            let completion: (QueryResult, Error?) -> () = { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }

            if queryDictionary {
                // This API can get word info, like pronunciation.
                webAppTranslate(processedText, from: from, to: to, completion: completion)
            } else {
                gtxTranslate(processedText, from: from, to: to, completion: completion)
            }
        }
    }

    // MARK: - Service Type & Configuration

    override func serviceType() -> ServiceType {
        .google
    }

    override func apiKeyRequirement() -> ServiceAPIKeyRequirement {
        .none
    }

    override func supportedQueryType() -> EZQueryTextType {
        [.dictionary, .sentence, .translation]
    }

    override func intelligentQueryTextType() -> EZQueryTextType {
        MyConfiguration.shared.intelligentQueryTextTypeForServiceType(serviceType())
    }

    override func name() -> String {
        NSLocalizedString("google_translate", comment: "")
    }

    override func link() -> String {
        kGoogleTranslateURL
    }

    // MARK: - Word Link

    /// https://translate.google.com/?sl=en&tl=zh-CN&text=good&op=translate
    override func wordLink(_ queryModel: QueryModel) -> String? {
        guard let from = languageCode(for: queryModel.queryFromLanguage),
              let to = languageCode(for: queryModel.queryTargetLanguage)
        else { return nil }

        let maxText = maxTextLength(
            queryModel.queryText,
            fromLanguage: queryModel.queryFromLanguage
        )
        let text = maxText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        return "\(kGoogleTranslateURL)/?sl=\(from)&tl=\(to)&text=\(text)&op=translate"
    }

    // MARK: - Supported Languages

    /// Google translate support languages: https://cloud.google.com/translate/docs/languages?hl=zh-cn
    override func supportLanguagesDictionary() -> MMOrderedDictionary {
        let languages: [Any] = [
            Language.auto, "auto",
            Language.simplifiedChinese, "zh-CN",
            Language.traditionalChinese, "zh-TW",
            Language.english, "en",
            Language.japanese, "ja",
            Language.korean, "ko",
            Language.french, "fr",
            Language.spanish, "es",
            Language.portuguese, "pt-PT",
            Language.brazilianPortuguese, "pt",
            Language.italian, "it",
            Language.german, "de",
            Language.russian, "ru",
            Language.arabic, "ar",
            Language.swedish, "sv",
            Language.romanian, "ro",
            Language.thai, "th",
            Language.slovak, "sk",
            Language.dutch, "nl",
            Language.hungarian, "hu",
            Language.greek, "el",
            Language.danish, "da",
            Language.finnish, "fi",
            Language.polish, "pl",
            Language.czech, "cs",
            Language.turkish, "tr",
            Language.lithuanian, "lt",
            Language.latvian, "lv",
            Language.ukrainian, "uk",
            Language.bulgarian, "bg",
            Language.indonesian, "id",
            Language.malay, "ms",
            Language.slovenian, "sl",
            Language.estonian, "et",
            Language.vietnamese, "vi",
            Language.persian, "fa",
            Language.hindi, "hi",
            Language.telugu, "te",
            Language.tamil, "ta",
            Language.urdu, "ur",
            Language.filipino, "tl",
            Language.khmer, "km",
            Language.lao, "lo",
            Language.bengali, "bn",
            Language.burmese, "my",
            Language.norwegian, "no",
            Language.serbian, "sr",
            Language.croatian, "hr",
            Language.mongolian, "mn",
            Language.hebrew, "iw",
            Language.georgian, "ka",
            NSNull(),
        ]

        let orderedDict = MMOrderedDictionary()
        for i in stride(from: 0, to: languages.count - 1, by: 2) {
            if let key = languages[i] as? NSObject,
               let value = languages[i + 1] as? NSObject {
                orderedDict.setObject(value, forKey: key)
            }
        }
        return orderedDict
    }

    // MARK: - Language Detection

    /// Detect language using Google web detection.
    @nonobjc
    override func detectText(_ text: String) async throws -> Language {
        try await withCheckedThrowingContinuation { continuation in
            webAppDetect(text) { language, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: language)
                }
            }
        }
    }

    /// Detect language for Objective-C callers without spawning a Task bridge.
    override func detectText(
        _ text: String,
        completionHandler: @escaping (Language, Error?) -> ()
    ) {
        webAppDetect(text) { language, error in
            DispatchQueue.main.async {
                completionHandler(language, error)
            }
        }
    }

    // MARK: - Text to Audio

    /// Generate audio URL using Google TTS.
    override func textToAudio(
        _ text: String,
        fromLanguage: Language,
        accent: String?
    ) async throws
        -> String? {
        guard !text.isEmpty else {
            throw QueryError(type: .parameter, message: "获取音频的文本为空")
        }

        let processedText = (text as NSString).trimmingToMaxLength(5000)

        if googleTTSMode == .api {
            if !googleCloudTTSAPIKey.isEmpty {
                do {
                    return try await cloudTextToAudio(
                        processedText,
                        fromLanguage: fromLanguage,
                        accent: accent
                    )
                } catch {
                    logError("Google Cloud TTS failed, fallback to web TTS: \(error)")
                }
            } else {
                logInfo("Google Cloud TTS mode is enabled, but API key is empty. Fallback to web TTS.")
            }
        }

        // TODO: need to optimize, Ref: https://github.com/florabtw/google-translate-tts/blob/master/src/synthesize.js

        if fromLanguage == .auto {
            let lang = try await detectText(processedText)
            let sign = signFunction.call(withArguments: [processedText])?.toString() ?? ""
            let url = getAudioURL(
                withText: processedText,
                language: getTTSLanguageCode(lang, accent: accent),
                sign: sign
            )
            return url
        }

        try await updateWebAppTKK()
        let sign = signFunction.call(withArguments: [processedText])?.toString() ?? ""
        let url = getAudioURL(
            withText: processedText,
            language: getTTSLanguageCode(fromLanguage, accent: accent),
            sign: sign
        )
        return url
    }

    // MARK: - Language Code Helpers

    internal override func languageEnum(fromCode code: String) -> Language {
        language(fromCode: code) ?? .auto
    }

    internal override func getTTSLanguageCode(_ language: Language, accent: String?) -> String {
        // TODO: Implement accent handling
        languageCode(for: language) ?? "en"
    }

    // MARK: - Audio URL

    func getAudioURL(withText text: String, language: String, sign: String) -> String {
        // TODO: text length must <= 200, maybe we can split it.
        let processedText = (text as NSString).trimmingToMaxLength(200)

        return
            "\(kGoogleTranslateURL)/translate_tts?ie=UTF-8&q=\(processedText.encode())&tl=\(language)&total=1&idx=0&textlen=\(processedText.count)&tk=\(sign)&client=webapp&prev=input"
    }

    // MARK: - Google Cloud TTS

    private var googleCloudTTSAPIKey: String {
        Defaults[.googleCloudTTSAPIKey].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var googleTTSMode: GoogleTTSMode {
        Defaults[.googleTTSMode]
    }

    private var googleCloudTTSVoiceName: String {
        Defaults[.googleCloudTTSVoiceName].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cloudTextToAudio(
        _ text: String,
        fromLanguage: Language,
        accent: String?
    ) async throws
        -> String? {
        let detectedLanguage: Language
        if fromLanguage == .auto {
            detectedLanguage = try await detectText(text)
        } else {
            detectedLanguage = fromLanguage
        }

        let languageCode = getTTSLanguageCode(detectedLanguage, accent: accent)

        let customVoice = matchedCloudVoiceName(for: languageCode)
        let voiceLanguageCode = cloudVoiceLanguageCode(for: customVoice) ?? languageCode
        let voice = GoogleCloudTTSRequest.Voice(languageCode: voiceLanguageCode, name: customVoice)

        let requestBody = GoogleCloudTTSRequest(
            input: .init(text: text),
            voice: voice,
            audioConfig: .init(audioEncoding: "MP3")
        )

        var components = URLComponents(string: "https://texttospeech.googleapis.com/v1/text:synthesize")
        components?.queryItems = [URLQueryItem(name: "key", value: googleCloudTTSAPIKey)]

        guard let url = components?.url else {
            throw QueryError(type: .api, message: "Invalid Google Cloud TTS URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QueryError(type: .api, message: "Invalid Google Cloud TTS response")
        }

        let cloudResponse = try JSONDecoder().decode(GoogleCloudTTSResponse.self, from: data)
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorMessage = cloudResponse.error?.message ?? "Google Cloud TTS request failed"
            throw QueryError(type: .api, message: errorMessage)
        }

        guard let audioContent = cloudResponse.audioContent,
              let audioData = Data(base64Encoded: audioContent)
        else {
            throw QueryError(type: .api, message: "Google Cloud TTS returned empty audio content")
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("easydict-google-cloud-tts-\(UUID().uuidString).mp3")
        try audioData.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    private func matchedCloudVoiceName(for languageCode: String) -> String? {
        let voiceName = googleCloudTTSVoiceName
        guard !voiceName.isEmpty else { return nil }

        let parts = voiceName.split(separator: "-")
        guard parts.count >= 2 else { return voiceName }

        let voiceLanguageCode = "\(parts[0])-\(parts[1])".lowercased()
        let normalizedLanguageCode = languageCode.lowercased()
        if normalizedLanguageCode.hasPrefix(voiceLanguageCode) {
            return voiceName
        }

        // Some language codes are generic (e.g. "en"). In that case, allow
        // regional voices that share the same base language (e.g. "en-US-*").
        if normalizedLanguageCode == parts[0].lowercased() {
            return voiceName
        }

        return nil
    }

    private func cloudVoiceLanguageCode(for voiceName: String?) -> String? {
        guard let voiceName else { return nil }
        let parts = voiceName.split(separator: "-")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])-\(parts[1])"
    }

    private struct GoogleCloudTTSRequest: Encodable {
        struct Input: Encodable {
            let text: String
        }

        struct Voice: Encodable {
            let languageCode: String
            let name: String?
        }

        struct AudioConfig: Encodable {
            let audioEncoding: String
        }

        let input: Input
        let voice: Voice
        let audioConfig: AudioConfig
    }

    private struct GoogleCloudTTSResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let audioContent: String?
        let error: APIError?
    }
}
