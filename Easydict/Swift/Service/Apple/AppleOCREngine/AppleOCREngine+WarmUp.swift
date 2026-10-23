//
//  AppleOCREngine+WarmUp.swift
//  Easydict
//
//  Created by tisfeng on 2026/9/26.
//  Copyright © 2026 izual. All rights reserved.
//

import CoreGraphics
import CoreText
import Defaults
import Foundation
import Vision

extension Defaults.Keys {
    /// The OS version whose Vision OCR networks the launch warm-up last compiled successfully.
    static let visionOCRWarmUpSystemVersion = Key<String?>("AppleOCREngine_visionOCRWarmUpSystemVersion")
}

// MARK: - AppleOCREngine + WarmUp

extension AppleOCREngine {
    // MARK: Internal

    /// Schedules a one-time background warm-up of the Vision OCR pipeline.
    ///
    /// On macOS 26/27 the `TextRecognition` framework's `*_e5.mlmodelc.bundle` resources ship
    /// without the pre-compiled `H13*.bundle` sub-bundles that e5rt expects, so e5rt falls back
    /// to compiling each network at runtime and logs `Unable to find a valid E5 in provided path
    /// ...`. A heavy network takes 26–28 seconds to compile, and the first OCR of a cold cache
    /// can stall for 60–120 seconds. The compiled artifacts are cached per app, so a single
    /// throwaway request at launch moves that cost off the user's first query.
    ///
    /// This runs at most once per process and returns immediately. The compiled artifacts are
    /// cached per OS build, so the warm-up is skipped once it has succeeded on the current OS
    /// version and the cache is still there: even with a warm cache, the request loads the
    /// detection, recognition and language correction models into the process, adding about
    /// 8 MB resident and a 77 MB launch peak for users who never use OCR. Any failure only means
    /// the first real OCR pays the original cost, which is why errors are logged instead of
    /// propagated.
    static func warmUpVisionOCRIfNeeded() {
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        if Defaults[.visionOCRWarmUpSystemVersion] == systemVersion, !isCompiledNetworkCacheMissing() {
            return
        }
        guard markWarmUpStarted() else { return }

        Task.detached(priority: .utility) {
            // Delay the request so it does not compete with launch-time work.
            try? await Task.sleep(for: .seconds(warmUpDelayInSeconds))
            if await performWarmUpOCR() {
                Defaults[.visionOCRWarmUpSystemVersion] = systemVersion
            }
        }
    }

    // MARK: Private

    /// Delay before the warm-up request starts, in seconds.
    private static let warmUpDelayInSeconds = 3

    private static let warmUpLock = NSLock()
    private static var hasStartedWarmUp = false

    /// Name of e5rt's compiled network cache folder inside the app's caches folder.
    private static let compiledNetworkCacheDirectoryName = "com.apple.e5rt.e5bundlecache"

    /// Whether the compiled network cache for the current OS build is missing, for example after
    /// a cache cleaner removed it.
    ///
    /// On macOS 26 and later, e5rt keeps the cache at
    /// `<Caches>/<bundle ID>/com.apple.e5rt.e5bundlecache/<OS build>/`. That layout is private, so
    /// if it ever changes this reports a missing cache and the warm-up simply runs at every launch
    /// again, as it did before the skip was added.
    private static func isCompiledNetworkCacheMissing() -> Bool {
        guard #available(macOS 26.0, *) else { return false }

        guard let osBuildVersion,
              let bundleID = Bundle.main.bundleIdentifier,
              let cachesDirectory = FileManager.default.urls(
                  for: .cachesDirectory, in: .userDomainMask
              ).first
        else {
            return true
        }

        let cacheDirectory = cachesDirectory
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(compiledNetworkCacheDirectoryName, isDirectory: true)
            .appendingPathComponent(osBuildVersion, isDirectory: true)
        let contents = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path)
        return contents?.isEmpty ?? true
    }

    /// The OS build version, such as `26A434`, which names e5rt's per-build cache directory.
    private static var osBuildVersion: String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Claims the one-shot warm-up slot, returning `true` only for the first caller.
    private static func markWarmUpStarted() -> Bool {
        warmUpLock.lock()
        defer { warmUpLock.unlock() }

        guard !hasStartedWarmUp else { return false }
        hasStartedWarmUp = true
        return true
    }

    /// Runs one throwaway OCR pass so Vision compiles its neural networks ahead of first use.
    ///
    /// - Returns: `true` when the request completed without error.
    private static func performWarmUpOCR() async -> Bool {
        guard let cgImage = makeWarmUpImage() else {
            logError("Vision OCR warm-up skipped: failed to synthesize the warm-up image")
            return false
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        logInfo("Warming up Vision OCR pipeline")

        // Mirror the API selection of `performVisionOCR(on:language:)` so the warm-up compiles
        // the same networks the first real query will need.
        let succeeded: Bool
        if #available(macOS 26.0, *) {
            succeeded = await performModernWarmUpOCR(on: cgImage)
        } else {
            succeeded = await performLegacyWarmUpOCR(on: cgImage)
        }

        logInfo("Vision OCR warm-up finished, cost time: \(startTime.elapsedTimeString) seconds")
        return succeeded
    }

    /// Warms up the modern `RecognizeTextRequest` pipeline (macOS 26.0+).
    @available(macOS 26.0, *)
    private static func performModernWarmUpOCR(on cgImage: CGImage) async -> Bool {
        var request = RecognizeTextRequest()
        configureWarmUpRequest(&request)

        do {
            _ = try await request.perform(on: cgImage)
            return true
        } catch {
            logError("Vision OCR warm-up failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Warms up the legacy `VNRecognizeTextRequest` pipeline.
    private static func performLegacyWarmUpOCR(on cgImage: CGImage) async -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = AppleLanguageMapper.shared.ocrRecognitionLanguageStrings(
            for: .auto
        )
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticLanguageDetectionEnabled(isModernOCR: false)

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            return true
        } catch {
            logError("Vision OCR warm-up failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Applies the recognition settings used by a real `.auto` query.
    ///
    /// The settings must match `performSingleModernVisionOCR(on:language:)` exactly, because the
    /// set of networks Vision compiles depends on the request configuration.
    @available(macOS 26.0, *)
    private static func configureWarmUpRequest(_ request: inout RecognizeTextRequest) {
        request.recognitionLevel = .accurate
        request.recognitionLanguages = AppleLanguageMapper.shared.ocrRecognitionLocaleLanguages(
            for: .auto, isModernOCR: true
        )
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticLanguageDetectionEnabled(isModernOCR: true)
    }

    /// Whether auto language detection stays on for an `.auto` query.
    ///
    /// `AppleLanguageMapper` has no entry for `.auto`, so the real path's `hasValidOCRLanguage(_:)`
    /// is `false` for `.auto` and both `performSingleModernVisionOCR(on:language:)` and
    /// `performSingleLegacyVisionOCR(on:language:)` enable auto-detection. `isModernOCR` is passed
    /// through so each warm-up branch mirrors its real counterpart.
    private static func automaticLanguageDetectionEnabled(isModernOCR: Bool) -> Bool {
        !AppleLanguageMapper.shared.isSupportedOCRLanguage(.auto, isModernOCR: isModernOCR)
    }

    /// Synthesizes a small image for the warm-up request.
    ///
    /// The set of networks Vision compiles is decided by the request configuration, not by the
    /// image: a synthetic image, a real screenshot, and an English-only request all compiled the
    /// same three networks in testing. The image only needs legible text, since an empty result
    /// can short-circuit before the recognition stage runs.
    private static func makeWarmUpImage() -> CGImage? {
        let width = 320
        let height = 96

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attributedText = NSAttributedString(
            string: "Easydict OCR 划词翻译",
            attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 36, nil),
                .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        context.textPosition = CGPoint(x: 12, y: 32)
        CTLineDraw(line, context)

        return context.makeImage()
    }
}
