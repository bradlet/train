//
//  ChartBucketing.swift
//  Train
//
//  Pure helpers behind the Progress charts (#31), shared by Cardio → Progress
//  and (later) Strength → Progress:
//
//  - `ChartBucketing` downsamples weekly points for the long scales: the
//    1-year chart plots one point per two weeks and the all-time chart one
//    per month, each the *average weekly value* across its weeks.
//  - `ChartAxis` picks the x-axis label dates — few, evenly spaced, and
//    never two in one month on the month-labelled scales. (Labelling every
//    week of an even-numbered month put four or five "Jun"s side by side,
//    which Charts truncated to "…": the 6-month axis bug.)
//  - `ChartGapStyle` decides how a series treats weeks with no value.
//
//  Unit-tested like `WorkoutAggregations` and `WeeklyChartSeries`.
//

import Foundation

// MARK: - Bucketing

/// How many weeks one plotted point covers.
enum ChartBucketSize: Equatable {
    /// One point per week (no downsampling).
    case week
    /// One point per two-week interval.
    case twoWeeks
    /// One point per calendar month.
    case month
}

/// Downsamples weekly points into longer buckets.
enum ChartBucketing {

    /// A fixed week every two-week bucket counts from, so buckets don't
    /// shift as weeks pass: Monday 2001-01-01 (any weekday works — only the
    /// week it falls in matters).
    private static let twoWeekEpoch = Date(timeIntervalSinceReferenceDate: 0)

    /// Averages weekly points into buckets.
    ///
    /// - Each bucket's value is the mean of its weeks' non-nil values; a
    ///   bucket whose weeks are all `nil` is `nil` (a gap, never 0).
    /// - Two-week buckets are aligned to a fixed epoch so a bucket is the
    ///   same pair of weeks whenever the chart is drawn; the first and last
    ///   bucket may hold one week (partial buckets).
    /// - Month buckets take each week by the month its first day falls in,
    ///   so a month holds four or five weeks, fewer at either end of the
    ///   range. A bucket's date is the start of its first week.
    /// - Parameters:
    ///   - points: Weekly points, oldest first.
    ///   - size: The bucket size.
    ///   - firstWeekday: Calendar weekday convention (1=Sunday ... 7=Saturday).
    /// - Returns: One point per bucket, oldest first.
    static func bucket(
        _ points: [WeeklyMetricPoint],
        size: ChartBucketSize,
        firstWeekday: Int
    ) -> [WeeklyMetricPoint] {
        guard size != .week else { return points }
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday
        let epochWeek = calendar.dateInterval(of: .weekOfYear, for: twoWeekEpoch)?.start ?? twoWeekEpoch

        var buckets: [(key: Int, start: Date, values: [Double])] = []
        for point in points {
            let key: Int
            switch size {
            case .week:
                key = 0
            case .twoWeeks:
                // Floor division throughout, so weeks before the epoch pair
                // up the same way as weeks after it.
                let days = calendar.dateComponents([.day], from: epochWeek, to: point.weekStart).day ?? 0
                let week = Int((Double(days) / 7).rounded(.down))
                key = Int((Double(week) / 2).rounded(.down))
            case .month:
                let parts = calendar.dateComponents([.year, .month], from: point.weekStart)
                key = (parts.year ?? 0) * 12 + (parts.month ?? 0)
            }
            if let last = buckets.last, last.key == key {
                if let value = point.value { buckets[buckets.count - 1].values.append(value) }
            } else {
                buckets.append((key, point.weekStart, point.value.map { [$0] } ?? []))
            }
        }
        return buckets.map { bucket in
            let value = bucket.values.isEmpty ? nil : bucket.values.reduce(0, +) / Double(bucket.values.count)
            return WeeklyMetricPoint(weekStart: bucket.start, value: value)
        }
    }
}

// MARK: - Axis labels

/// X-axis label placement.
enum ChartAxis {

    /// The most labels an axis shows; fewer, cleaner labels read better at
    /// phone width.
    static let maxLabels = 5

    /// Evenly spaced label dates.
    ///
    /// - Day-labelled scales: every k-th point, starting with the first,
    ///   with k chosen so at most `maxLabels` fit.
    /// - Month-labelled scales: the first point of each month (so a month is
    ///   never labelled twice), thinned to every k-th month the same way.
    /// - A label on the final point is dropped (it would sit on the edge).
    /// - Parameters:
    ///   - dates: The plotted dates, oldest first.
    ///   - monthly: Whether labels show months only.
    ///   - maxLabels: The label budget.
    static func labelDates(_ dates: [Date], monthly: Bool, maxLabels: Int = ChartAxis.maxLabels) -> [Date] {
        guard maxLabels > 0 else { return [] }
        let candidates: [Date]
        if monthly {
            let calendar = Calendar.current
            var seen = Set<Int>()
            candidates = dates.filter { date in
                let parts = calendar.dateComponents([.year, .month], from: date)
                return seen.insert((parts.year ?? 0) * 12 + (parts.month ?? 0)).inserted
            }
        } else {
            candidates = dates
        }
        guard !candidates.isEmpty else { return [] }
        let stride = Int((Double(candidates.count) / Double(maxLabels)).rounded(.up))
        var labels = candidates.enumerated().filter { $0.offset % max(stride, 1) == 0 }.map(\.element)
        // A label on the very last point sits on the chart's trailing edge,
        // where Charts drops it and leaves a bare tick.
        if labels.count > 2, labels.last == dates.last { labels.removeLast() }
        return labels
    }
}

// MARK: - Missing data

/// How a chart series treats points with no value.
enum ChartGapStyle: Equatable {
    /// Break the line at missing points (each run its own series).
    case breakLine
    /// Draw the data as runs and bridge each gap with a dashed connector,
    /// so the trend reads continuously without inventing a point.
    case bridge
    /// Plot missing points as zero (an empty week of mileage *is* zero).
    case zero
}

/// One drawable run of a series.
struct ChartRun: Identifiable, Equatable {
    /// Chronological run number; doubles as the Charts series id.
    let id: Int
    /// The run's points, all with values.
    let points: [WeeklyMetricPoint]
    /// Whether this run is a dashed bridge across a gap (two points: the
    /// last value before the gap and the first after it).
    let isBridge: Bool

    /// A one-point data run, which needs an explicit dot.
    var isSingleton: Bool { !isBridge && points.count == 1 }
}

/// Builds drawable runs from points and a gap style.
enum ChartSeriesBuilder {

    /// The runs to draw.
    /// - Parameters:
    ///   - points: Points, oldest first.
    ///   - style: How to treat missing values.
    static func runs(_ points: [WeeklyMetricPoint], style: ChartGapStyle) -> [ChartRun] {
        switch style {
        case .zero:
            let filled = points.map { WeeklyMetricPoint(weekStart: $0.weekStart, value: $0.value ?? 0) }
            return filled.isEmpty ? [] : [ChartRun(id: 0, points: filled, isBridge: false)]
        case .breakLine:
            return WeeklyChartSeries.segments(points).map { ChartRun(id: $0.id, points: $0.points, isBridge: false) }
        case .bridge:
            let segments = WeeklyChartSeries.segments(points)
            var runs: [ChartRun] = []
            for (index, segment) in segments.enumerated() {
                if index > 0, let end = segments[index - 1].points.last, let start = segment.points.first {
                    runs.append(ChartRun(id: runs.count, points: [end, start], isBridge: true))
                }
                runs.append(ChartRun(id: runs.count, points: segment.points, isBridge: false))
            }
            return runs
        }
    }
}
