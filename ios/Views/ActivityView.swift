import Charts
import SwiftUI

struct ActivityView: View {
    @StateObject var viewModel: ActivityViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    rangePicker
                    filterPicker

                    switch viewModel.state {
                    case .idle, .loading:
                        LoadingOverlay(title: "Loading activity")
                            .frame(height: 220)
                    case .failed(let message):
                        ErrorStateView(title: "Unable to Load Activity", message: message) {
                            Task { await viewModel.load() }
                        }
                    case .loaded(let items):
                        summarySection
                        trendSection
                        timelineSection(items)
                    }
                }
                .padding()
            }
            .background(AppColors.groupedBackground)
            .navigationTitle("Activity")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Motion history and trends")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var rangePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityDateRange.allCases) { range in
                    Button {
                        viewModel.selectedRange = range
                        Task { await viewModel.load() }
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minWidth: 74)
                            .background(viewModel.selectedRange == range ? Color.blue : AppColors.secondaryGroupedBackground, in: Capsule())
                            .foregroundStyle(viewModel.selectedRange == range ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $viewModel.selectedFilter) {
            ForEach(ActivityEventKind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: viewModel.selectedFilter) {
            viewModel.applyFilter()
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 24 Hours")
                .font(.title2.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(title: "Sensor triggers", value: "\(viewModel.pastDayMotionCount)", systemImage: "figure.walk")
                MetricCard(title: "Since last activity", value: inactivityValue, systemImage: "timer")
                MetricCard(title: "Longest gap", value: longestGapValue, systemImage: "moon")
                MetricCard(title: "Latest activity", value: viewModel.activityComparison, systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }

    private var inactivityValue: String {
        guard let currentInactivity = viewModel.currentInactivity else {
            return "No activity"
        }
        return Formatters.duration(currentInactivity)
    }

    private var longestGapValue: String {
        guard let longestInactivityPastDay = viewModel.longestInactivityPastDay else {
            return "No activity"
        }
        return Formatters.duration(longestInactivityPastDay)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seven-Day Trend")
                .font(.title2.weight(.bold))
            Chart(viewModel.trends) { day in
                BarMark(
                    x: .value("Day", Formatters.day.string(from: day.date)),
                    y: .value("Visits", day.visits)
                )
                .foregroundStyle(.blue)
            }
            .frame(height: 180)
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func timelineSection(_ items: [ActivityTimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.title2.weight(.bold))
            if items.isEmpty {
                EmptyStateView(title: "No Events", message: "No matching activity is available for this range.", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.groupedTimelineItems(items), id: \.title) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.headline)
                            ActivityTimeline(items: group.items)
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
