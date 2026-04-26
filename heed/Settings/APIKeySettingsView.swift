import SwiftUI

struct APIKeySettingsView: View {
    @ObservedObject var viewModel: APIKeySettingsViewModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI API key")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HeedTheme.ColorToken.textPrimary)

                    Text("Heed stores this key in Keychain.")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                }

                Spacer(minLength: 12)

                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
            }

            SecureField("sk-...", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .accessibilityIdentifier("api-key-field")

            Text(viewModel.statusMessage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Save") {
                    viewModel.saveAPIKey()
                }
                .buttonStyle(
                    HeedTransportButtonStyle(
                        fillColor: HeedTheme.ColorToken.actionYellow,
                        textColor: Color.black.opacity(0.8),
                        size: .compact
                    )
                )
                .accessibilityIdentifier("api-key-save")

                Button("Clear") {
                    viewModel.clearAPIKey()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
                .accessibilityIdentifier("api-key-clear")

                Spacer(minLength: 12)
            }

            Divider()
                .overlay(HeedTheme.ColorToken.borderSubtle)

            VStack(alignment: .leading, spacing: 6) {
                Text("Composio API key")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HeedTheme.ColorToken.textPrimary)

                Text("This lets the prep agent use Gmail, Google Calendar, and Google Drive tools through Composio.")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("composio-...", text: $viewModel.composioAPIKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .accessibilityIdentifier("composio-api-key-field")

            Text(viewModel.composioStatusMessage)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Save Composio") {
                    viewModel.saveComposioAPIKey()
                }
                .buttonStyle(
                    HeedTransportButtonStyle(
                        fillColor: HeedTheme.ColorToken.actionYellow,
                        textColor: Color.black.opacity(0.8),
                        size: .compact
                    )
                )
                .accessibilityIdentifier("composio-api-key-save")

                Button("Clear Composio") {
                    viewModel.clearComposioAPIKey()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(HeedTheme.ColorToken.textPrimary.opacity(0.82))
                .accessibilityIdentifier("composio-api-key-clear")

                Spacer(minLength: 12)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(HeedTheme.ColorToken.canvas)
        .onAppear {
            viewModel.loadStoredAPIKey()
        }
    }
}
