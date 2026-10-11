import SwiftUI

/// The hardware silhouette traced from the Hades Canyon lid photo.
/// The menu-bar version is a template image so macOS uses the same monochrome
/// tint as neighboring status items while retaining the original geometry.
struct HadesSkullSymbol: View {
    var body: some View {
        Image("HadesSkullTemplate", bundle: .module)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// The same traced mark in its original blue and red LED colors, used in the
/// panel and in the generated application icon.
struct HadesSkullBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.15, blue: 0.23), Color(red: 0.025, green: 0.04, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image("HadesSkullColor", bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 0.88)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
