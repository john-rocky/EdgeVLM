//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AppIntents
import CoreImage
import EdgeVLM
import MLXLMCommon
import MLXVLM

struct AnalyzeImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Analyze Image"
    static var description = IntentDescription("Analyze an image using EdgeVLM on-device AI")

    @Parameter(title: "Image")
    var image: IntentFile

    @Parameter(title: "Prompt", default: "Describe this image.")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$image) with prompt \(\.$prompt)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let imageData = image.data
        guard let ciImage = CIImage(data: imageData) else {
            throw AnalyzeImageError.invalidImage
        }

        let model = await EdgeVLMModel()
        let userInput = UserInput(
            prompt: .text(prompt),
            images: [.ciImage(ciImage)]
        )

        let result = try await model.generateCaption(userInput)
        return .result(value: result)
    }

    enum AnalyzeImageError: Error, CustomLocalizedStringResourceConvertible {
        case invalidImage
        case analysisFailed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .invalidImage: return "Could not read the image"
            case .analysisFailed: return "Image analysis failed"
            }
        }
    }
}
