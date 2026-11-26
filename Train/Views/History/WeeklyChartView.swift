//
//  WeeklyChartView.swift
//  Train
//
//  Pages 2 and 3 of the Performance Hub. A parameterized line chart
//  that displays a weekly metric (mileage or average feeling) over
//  a selectable scale (1M / 3M / 6M / 1Y / All; the long scales downsample). A single view is reused
//  for both charts because they differ only in data source, y-scale,
//  and axis label — captured in `WeeklyChartConfiguration`.
//

import SwiftUI
import SwiftData
import Charts

/// Selectable time scales for the Progress charts. The longer scales
/// downsample (see `ChartBucketing`): 1Y plots one point per two weeks and
/// All one per month, each the average weekly value across its weeks.
enum PerformanceTimeWindow: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonth
    case sixMonth
    case oneYear
    case allTime

    var id: String { rawValue }

    /// Short label for the segmented pill.
    var label: String {
        switch self {
        case .oneMonth:   return "1M"
        case .threeMonth: return "3M"
        case .sixMonth:   return "6M"
        case .oneYear:    return "1Y"
        case .allTime:    return "All"
        }
    }

    /// How many weeks one plotted point covers.
    var bucketSize: ChartBucketSize {
        switch self {
        case .oneMonth, .threeMonth, .sixMonth: return .week
        case .oneYear:  return .twoWeeks
        case .allTime:  return .month
        }
    }

    /// Whether x-axis labels show months only ("Apr") rather than a day
    /// ("Apr 6").
    var monthlyLabels: Bool {
        switch self {
        case .oneMonth, .threeMonth: return false
        case .sixMonth, .oneYear, .allTime: return true
        }
    }

    /// Weeks of weekly data the scale covers, ending with the current week.
    /// All time reaches back to the week of the earliest data (at least
    /// four weeks, so a new athlete's chart isn't a single point).
    /// - Parameters:
    ///   - earliest: The earliest data date, if any.
    ///   - now: The current moment.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    func weekCount(earliest: Date?, now: Date, firstWeekday: Int) -> Int {
        switch self {
        case .oneMonth:   return 4
        case .threeMonth: return 13
        case .sixMonth:   return 26
        case .oneYear:    return 52
        case .allTime:
            guard let earliest, earliest < now else { return 4 }
            let first = earliest.startOfWeek(firstWeekday: firstWeekday)
            let current = now.startOfWeek(firstWeekday: firstWeekday)
            let days = Calendar.current.dateComponents([.day], from: first, to: current).day ?? 0
            return max(Int((Double(days) / 7).rounded()) + 1, 4)
        }
    }
}

/// Per-chart configuration that slots into the shared `WeeklyChartView`
/// body. Captures the small differences between the mileage and feeling
/// variants (data source and y-scale).
struct WeeklyChartConfiguration {
    /// Title shown above the chart.
    let title: String
    /// Fixed y-axis domain, or `nil` to auto-scale from the data.
    let fixedYScale: ClosedRange<Double>?
    /// Spacing between y-axis ticks, or `nil` for automatic placement. Short
    /// fixed domains pin a stride so Charts labels every step of the scale
    /// (including its maximum) instead of every other one.
    let yAxisStride: Double?
    /// How weeks without a value are drawn.
    let gapStyle: ChartGapStyle
    /// Projects recorded exercises into weekly points. The last parameter
    /// is the first weekday of the aggregation week (1=Sunday ... 7=Saturday).
    let projection: (_ exercises: [Exercise], _ weekCount: Int, _ anchor: Date, _ firstWeekday: Int) -> [WeeklyMetricPoint]

    static let mileage = WeeklyChartConfiguration(
        title: "Weekly Mileage",
        fixedYScale: nil,
        yAxisStride: nil,
        gapStyle: .zero,
        projection: WorkoutAggregations.weeklyMileage
    )

    /// Feeling runs 1–5, but the domain starts at 0 so a "Very Weak" week
    /// isn't glued to the frame's bottom edge. Unrated weeks are never
    /// plotted: a dashed bridge spans them so the trend still reads.
    static let feeling = WeeklyChartConfiguration(
        title: "How it's been feeling",
        fixedYScale: 0...5,
        yAxisStride: 1,
        gapStyle: .bridge,
        projection: WorkoutAggregations.weeklyAverageFeeling
    )
}

/// Parameterized line chart for a weekly metric. Shows the Performance
/// Hub's mileage and feeling charts via `WeeklyChartConfiguration`.
struct WeeklyChartView: View {
    let exercises: [Exercise]
    let configuration: WeeklyChartConfiguration

    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.weekStartDay) private var weekStartDay
    @State private var selectedWindow: PerformanceTimeWindow = .oneMonth

    /// Points for the current scale: weekly values from the projection,
    /// downsampled for the long scales. Valueless points stay `nil`.
    private var points: [WeeklyMetricPoint] {
        let now = Date()
        let earliest = exercises.map(\.date).min()
        let weeks = selectedWindow.weekCount(earliest: earliest, now: now, firstWeekday: weekStartDay)
        let weekly = configuration.projection(exercises, weeks, now, weekStartDay)
        return ChartBucketing.bucket(weekly, size: selectedWindow.bucketSize, firstWeekday: weekStartDay)
    }

    /// Drawable runs per the configuration's gap style.
    private var runs: [ChartRun] {
        ChartSeriesBuilder.runs(points, style: configuration.gapStyle)
    }

    /// Pinned x-domain spanning the whole scale, so a scale whose data sits
    /// in its last weeks still spans the full range.
    private var xDomain: ClosedRange<Date> {
        let dates = points.map(\.weekStart)
        guard let first = dates.first, let last = dates.last, first < last else {
            let now = Date()
            return now.addingTimeInterval(-7 * 86_400)...now
        }
        return first...last
    }

    /// X-axis label dates: at most `ChartAxis.maxLabels`, one per month at
    /// most on the month-labelled scales.
    private var labelDates: [Date] {
        ChartAxis.labelDates(points.map(\.weekStart), monthly: selectedWindow.monthlyLabels)
    }

    /// Point symbols get in the way once a line has many points.
    private var showsSymbols: Bool { points.count <= 26 }

    /// Y-scale domain for the chart. Rating charts clamp to their fixed
    /// scale; mileage auto-scales to the max value with a zero baseline so
    /// short/flat weeks are still visible.
    private var yScaleDomain: ClosedRange<Double> {
        if let fixed = configuration.fixedYScale {
            return fixed
        }
        let maxValue = points.compactMap(\.value).max() ?? 0
        // Minimum ceiling of 1 so an all-zero week still renders a baseline.
        let ceiling = max(maxValue * 1.1, 1)
        return 0...ceiling
    }

    /// Y-axis tick placement for this chart.
    private var yAxisValues: AxisMarkValues {
        guard let stride = configuration.yAxisStride else { return .automatic }
        return .stride(by: stride)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(configuration.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                ForEach(runs) { run in
                    ForEach(run.points) { point in
                        LineMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Value", point.value ?? 0),
                            series: .value("Run", run.id)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(run.isBridge ? Color.accentColor.opacity(0.5) : Color.accentColor)
                        .lineStyle(run.isBridge
                                   ? StrokeStyle(lineWidth: 1.5, dash: [3, 4])
                                   : StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .symbol {
                            if showsSymbols && !run.isBridge {
                                Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                // A one-point run has a zero-length path and so draws nothing.
                ForEach(runs.filter(\.isSingleton)) { run in
                    if let point = run.points.first, let value = point.value {
                        PointMark(
                            x: .value("Week", point.weekStart),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(30)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yScaleDomain)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisValues) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text("\(Int(d))")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: labelDates) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    if selectedWindow == .allTime {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits), collisionResolution: .greedy)
                    } else if selectedWindow.monthlyLabels {
                        AxisValueLabel(format: .dateTime.month(.abbreviated), collisionResolution: .greedy)
                    } else {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy)
                    }
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.35), value: selectedWindow)
            .animation(.easeInOut(duration: 0.35), value: useMetricUnits)

            Picker("Window", selection: $selectedWindow) {
                ForEach(PerformanceTimeWindow.allCases) { window in
                    Text(window.label).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("weeklyChart.window.\(configuration.title)")
        }
    }
}

#Preview("Mileage") {
    WeeklyChartView(exercises: [], configuration: .mileage)
        .padding()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}

#Preview("Feeling") {
    WeeklyChartView(exercises: [], configuration: .feeling)
        .padding()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
