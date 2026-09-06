import SwiftUI

enum Style {
    static let green = Color(red: 0.12, green: 0.40, blue: 0.30)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let cameraBackground = Color(red: 0.06, green: 0.08, blue: 0.07)

    static func duration(_ seconds: Double) -> String {
        let value = max(0, seconds.isFinite ? Int(seconds) : 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct WideButton: View {
    let title: String
    let icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

