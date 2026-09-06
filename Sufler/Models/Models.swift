import Foundation
import SwiftData
#if SWIFT_PACKAGE
import SuflerCore
#endif

@Model final class Script {
    @Attribute(.unique) var id: UUID
    var title: String
    var text: String
    var updatedAt: Date

    init(title: String = "Новый текст", text: String = "") {
        id = UUID(); self.title = title; self.text = text; updatedAt = Date()
    }
}

@Model final class PromptSettings {
    @Attribute(.unique) var key: String
    var fontSize: Double
    var lineSpacing: Double
    var widthFraction: Double
    var backgroundOpacity: Double
    var speed: Double
    var countdown: Int
    var mirrorVideo: Bool
    var didSeedExample: Bool

    init() {
        key = "default"; fontSize = 32; lineSpacing = 10; widthFraction = 0.9
        backgroundOpacity = 0.65; speed = 38; countdown = 3; mirrorVideo = false; didSeedExample = false
    }
}

@Model final class Take {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var status: String
    var note: String?
    var savedToPhotos: Bool

    init(intent: TakeIntent) {
        id = intent.id; title = intent.title; createdAt = intent.createdAt
        duration = 0; status = "pending"; savedToPhotos = false
    }
}
