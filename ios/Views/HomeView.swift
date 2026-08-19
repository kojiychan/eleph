import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel
    let viewAllActivity: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch viewModel.state {
                    case .idle, .loading:
                        LoadingOverlay(title: "Loading home")
                            .frame(height: 360)
                    case .failed(let message):
                        ErrorStateView(title: "Unable to Load Home", message: message) {
                            Task { await viewModel.load() }
                        }
                    case .loaded(let snapshot):
                        homeContent(snapshot)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Home")
            .homeToolbar()
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func homeContent(_ snapshot: AppSnapshot) -> some View {
        let summary = snapshot.summaries.first
        let currentInactivity = summary?.currentInactivity ?? viewModel.inactivitySinceLastMotion(snapshot.device)
        let isOffline = snapshot.device.connectionStatus == .offline

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(name: snapshot.profile.caregiverName))
                    .font(.largeTitle.weight(.bold))
                Text(snapshot.device.displayName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.plainStatus(for: snapshot))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isOffline ? .orange : .primary)
                Spacer()
                if viewModel.isUsingMockData {
                    Label("Demo data", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryGroupedBackground, in: Capsule())
                }
            }

            if let lastUpdatedAt = viewModel.lastUpdatedAt {
                Text("Last updated \(Formatters.relative(lastUpdatedAt))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            DeviceConnectionBanner(device: snapshot.device)

            StatusCard(
                state: viewModel.wellnessState(for: snapshot),
                lastMotionAt: snapshot.device.lastMotionAt,
                isDataStale: isOffline
            )

            InactivityProgressBar(
                currentInactivity: currentInactivity,
                cautionThresholdHours: snapshot.alertPreferences.cautionThresholdHours,
                criticalThresholdHours: snapshot.alertPreferences.criticalThresholdHours
            )

            dailySummary(summary, device: snapshot.device)

            recentActivity(snapshot.motionEvents.prefix(3).map { $0 })
        }
    }

    private func dailySummary(_ summary: DailyActivitySummary?, device: MonitorDevice) -> some View {
        let status: BathroomMotionState = device.connectionStatus == .offline ? .monitorOffline : (summary?.currentBathroomState ?? .empty)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title2.weight(.bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(title: "Bathroom visits", value: "\(summary?.visits ?? 0)", systemImage: "figure.walk")
                MetricCard(title: "Current inactivity", value: Formatters.duration(summary?.currentInactivity ?? 0), systemImage: "timer")
                MetricCard(title: "Longest inactivity", value: Formatters.duration(summary?.longestInactivity ?? 0), systemImage: "moon.zzz")
                MetricCard(title: "Bathroom status", value: status.rawValue, systemImage: "sensor.tag.radiowaves.forward", tint: device.connectionStatus.tint)
            }
        }
    }

    private func recentActivity(_ events: [MotionEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.title2.weight(.bold))
                Spacer()
                Button("View All", action: viewAllActivity)
            }

            if events.isEmpty {
                EmptyStateView(title: "No motion recorded yet today", message: "Activity updates will appear here when the monitor detects motion.", systemImage: "clock.badge.questionmark")
                    .frame(minHeight: 170)
            } else {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        MotionEventRow(event: event)
                        if event.id != events.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func greeting(name: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<12: prefix = "Good Morning"
        case 12..<17: prefix = "Good Afternoon"
        default: prefix = "Good Evening"
        }
        return "\(prefix), \(name)"
    }
}

private extension View {
    @ViewBuilder
    func homeToolbar() -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "bell")
                }
                .accessibilityLabel("Notifications")
            }
        }
        #else
        toolbar {
            Button {
            } label: {
                Image(systemName: "bell")
            }
            .accessibilityLabel("Notifications")
        }
        #endif
    }
}

#Preview("Normal") {
    MainTabPreview(scenario: .normalOnline)
}

#Preview("Offline") {
    MainTabPreview(scenario: .offlineSeveralHours)
}
