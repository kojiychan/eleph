import Charts
import SwiftUI

struct ActivityView: View {
    @StateObject var viewModel: ActivityViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    datePicker
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

    private var datePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.datesForPicker(), id: \.self) { date in
                    Button {
                        viewModel.selectedDate = date
                        Task { await viewModel.load() }
                    } label: {
                        Text(Calendar.current.isDateInToday(date) ? "Today" : Formatters.day.string(from: date))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate) ? Color.blue : AppColors.secondaryGroupedBackground, in: Capsule())
                            .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate) ? .white : .primary)
                    }
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
        let summary = viewModel.summaries.first
        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily Summary")
                .font(.title2.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricCard(title: "Motion sessions", value: "\(summary?.visits ?? 0)", systemImage: "figure.walk")
                MetricCard(title: "Current inactivity", value: Formatters.duration(summary?.currentInactivity ?? 0), systemImage: "timer")
                MetricCard(title: "Longest inactivity", value: Formatters.duration(summary?.longestInactivity ?? 0), systemImage: "moon")
                MetricCard(title: "Compared with usual", value: summary?.comparison ?? "No comparison yet", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
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
                EmptyStateView(title: "No Events", message: "No matching activity is available for this date.", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(minHeight: 180)
            } else {
                ActivityTimeline(items: items)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
