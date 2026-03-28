//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import AppIntents
import CoreImage
import EdgeVLM
import MLXLMCommon
import MLXVLM

struct ReadTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Read Text in Image"
    static var description = IntentDescription("Extract text from an image using EdgeVLM")

    @Parameter(title: "Image")
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Read text in \(\.$image)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let imageData = image.data
        guard let ciImage = CIImage(data: imageData) else {
            throw ReadTextError.invalidImage
        }

        let model = await EdgeVLMModel()
        let userInput = UserInput(
            prompt: .text("Read all text visible in this image. Output only the text content."),
            images: [.ciImage(ciImage)]
        )

        let result = try await model.generateCaption(userInput)
        return .result(value: result)
    }

    enum ReadTextError: Error, CustomLocalizedStringResourceConvertible {
        case invalidImage

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .invalidImage: return "Could not read the image"
            }
        }
    }
}
