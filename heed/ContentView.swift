//
//  ContentView.swift
//  heed
//
//  Created by Sparsh Shah on 2026-04-08.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var controller: RecordingController

    init(controller: RecordingController) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        NavigationSplitView {
            SessionSidebar(
                sessions: controller.sessions,
                selectedSessionID: controller.selectedSession?.id,
                onSelect: controller.selectSession(_:)
            )
            .frame(minWidth: 250)
        } detail: {
            TranscriptWorkspace(controller: controller)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.black)
    }
}

private struct SessionSidebar: View {
    let sessions: [TranscriptSession]
    let selectedSessionID: UUID?
    let onSelect: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
                .padding(16)

            Divider()
                .overlay(Color.white)

            if sessions.isEmpty {
                Text("No saved sessions yet.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(selection: .constant(selectedSessionID)) {
                    ForEach(sessions) { session in
                        Button {
                            onSelect(session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.body, design: .monospaced).weight(.bold))
                                Text(session.status.rawValue.uppercased())
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            session.id == selectedSessionID ? Color.white.opacity(0.12) : Color.black
                        )
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.black)
            }
        }
        .background(Color.black)
    }
}

private struct TranscriptWorkspace: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(controller: controller)
            Divider().overlay(Color.white)
            TranscriptList(
                segments: controller.activeSession?.segments ?? controller.selectedSession?.segments ?? [],
                autoScrollEnabled: $controller.autoScrollEnabled
            )
            Divider().overlay(Color.white)
            FooterBar(controller: controller)
        }
        .background(Color.black)
    }
}

private struct HeaderBar: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Heed")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
            HStack(alignment: .center, spacing: 16) {
                Button(controller.primaryButtonTitle) {
                    controller.handlePrimaryAction()
                }
                .buttonStyle(BrutalistButtonStyle(accent: controller.state == .recording ? .red : .white))
                .accessibilityIdentifier("record-button")

                Text(controller.state.statusText.uppercased())
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(Rectangle().stroke(Color.white, lineWidth: 1))

                Text(controller.elapsedTime.heedClockString)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Text(controller.errorMessage ?? controller.permissions.guidanceText)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}

private struct TranscriptList: View {
    let segments: [TranscriptSegment]
    @Binding var autoScrollEnabled: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if segments.isEmpty {
                        Text("Press Record to request permissions and begin local transcription.")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("empty-state")
                    } else {
                        ForEach(segments) { segment in
                            SegmentRow(segment: segment)
                                .id(segment.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("timeline-bottom")
                        .onAppear {
                            autoScrollEnabled = true
                        }
                        .onDisappear {
                            autoScrollEnabled = false
                        }
                }
            }
            .background(Color.black)
            .onChange(of: segments.count) {
                guard autoScrollEnabled else {
                    return
                }
                withAnimation(.linear(duration: 0.15)) {
                    proxy.scrollTo("timeline-bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct SegmentRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(segment.source.label)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(segment.source == .mic ? Color.green : Color.orange)
                .frame(width: 88, alignment: .leading)
                .padding(12)
                .overlay(Rectangle().stroke(Color.white, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text(segment.startedAt.heedClockString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text(segment.text)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
        }
        .accessibilityIdentifier("segment-\(segment.source.rawValue)")
    }
}

private struct FooterBar: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        HStack(spacing: 12) {
            Button("Copy as text") {
                controller.copySelectedSession()
            }
            .buttonStyle(BrutalistButtonStyle(accent: .white))
            .disabled(controller.selectedSession == nil)

            Button("Export .txt") {
                controller.exportSelectedSession(as: .text)
            }
            .buttonStyle(BrutalistButtonStyle(accent: .white))
            .disabled(controller.selectedSession == nil)

            Button("Export .md") {
                controller.exportSelectedSession(as: .markdown)
            }
            .buttonStyle(BrutalistButtonStyle(accent: .white))
            .disabled(controller.selectedSession == nil)

            Spacer()

            Button("Refresh Permissions") {
                controller.refreshPermissions()
            }
            .buttonStyle(BrutalistButtonStyle(accent: .white))
        }
        .padding(20)
    }
}

private struct BrutalistButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .monospaced).weight(.bold))
            .foregroundStyle(configuration.isPressed ? Color.black : accent == .white ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? accent.opacity(0.8) : accent)
            .overlay(Rectangle().stroke(Color.white, lineWidth: 1))
    }
}

private extension TimeInterval {
    var heedClockString: String {
        let totalSeconds = Int(self.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    ContentView(controller: RecordingController(demoMode: true))
}
