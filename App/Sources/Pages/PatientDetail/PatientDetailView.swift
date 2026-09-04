import SwiftUI
import Charts
import FHIRCore

// MARK: - Display Helpers

private extension PatientDetailViewModel.VitalSeries {

  /// 已知的 LOINC code 用在地化名稱，未知的沿用 server 給的文字。
  ///
  /// 只認 code 不認 display，是因為同一個項目在不同 server 上的 display 可能是英文、
  /// 縮寫或空白。code 才是穩定的識別。
  var title: String {
    switch code {
    case LOINC.bodyTemperature: String(localized: "Temperature")
    case LOINC.heartRate: String(localized: "Heart Rate")
    case LOINC.respiratoryRate: String(localized: "Respiratory Rate")
    case LOINC.oxygenSaturation: String(localized: "Oxygen Saturation")
    case LOINC.systolicBP: String(localized: "Systolic Blood Pressure")
    case LOINC.diastolicBP: String(localized: "Diastolic Blood Pressure")
    default: serverDisplay
    }
  }

  /// 已知的 UCUM 單位用在地化符號，未知的沿用 server 給的文字。
  ///
  /// 對照的鍵是 `Quantity.code`（UCUM）而不是 LOINC code——單位屬於「這個數值是什麼」，
  /// 不能從項目種類反推。server 送華氏就該顯示華氏，否則等於竄改數值的意義。
  var unitLabel: String {
    switch unitCode {
    case "Cel": String(localized: "°C")
    case "[degF]": String(localized: "°F")
    case "%": String(localized: "%")
    case "/min": String(localized: "/min")
    case "mm[Hg]": String(localized: "mmHg")
    case "kg": String(localized: "kg")
    case "cm": String(localized: "cm")
    default: serverUnit
    }
  }

  /// 縱軸的顯示範圍。
  ///
  /// 同時涵蓋資料點與參考範圍，再往外留一點餘裕——否則貼著邊界的點會被切掉，
  /// 而參考範圍的帶子可能整條落在視野外。
  var valueRange: ClosedRange<Double> {
    var low = points.map(\.value).min() ?? 0
    var high = points.map(\.value).max() ?? 1

    if let bounds = referenceRange {
      low = min(low, bounds.low ?? low)
      high = max(high, bounds.high ?? high)
    }

    let padding = max((high - low) * 0.15, 0.5)
    return (low - padding)...(high + padding)
  }
}

// MARK: - PatientDetailView

struct PatientDetailView: View {

  let viewModel: PatientDetailViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        IdentitySection(patient: viewModel.state.patient)
        vitals()
      }
      .padding(20)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(viewModel.state.patient.name)
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  // 先看有沒有內容、再看狀態：刷新失敗時已畫出的圖不該消失。
  @ViewBuilder private func vitals() -> some View {
    if viewModel.state.series.isEmpty {
      switch viewModel.state.api.loadVitals {
      case .prepare, .loading:
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 200)

      case let .error(message):
        ContentUnavailableView {
          Label("Can't load vital signs", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }
        .frame(minHeight: 200)

      case .success:
        ContentUnavailableView(
          "No vital signs recorded",
          systemImage: "waveform.path.ecg"
        )
        .frame(minHeight: 200)
      }
    } else {
      VitalsSection(
        series: viewModel.state.series,
        failureMessage: viewModel.state.api.loadVitals.failureMessage
      )
    }
  }
}

private extension PatientDetailViewModel.Status {

  /// 已有內容時的失敗，只作為附加提示，不取代內容。
  var failureMessage: String? {
    if case let .error(message) = self { return message }
    return nil
  }
}

// MARK: - Identity

private extension PatientDetailView {

  struct IdentitySection: View {

    let patient: PatientDetailViewModel.PatientIdentity

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        Text(patient.name)
          .font(.title2.weight(.semibold))

        HStack(spacing: 6) {
          if let gender = patient.gender {
            Text(gender)
          }
          if let age = patient.age {
            Text("· \(age) yrs")
          }
          // 缺漏的欄位整段省略，不留空白佔位
          if let recordNumber = patient.recordNumber {
            Text("· \(recordNumber)")
              .monospacedDigit()
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
      .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
  }
}

// MARK: - Vitals

private extension PatientDetailView {

  struct VitalsSection: View {

    let series: [PatientDetailViewModel.VitalSeries]
    let failureMessage: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        if let failureMessage {
          // 已經有圖了，失敗只作為附加提示
          Label(failureMessage, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        ForEach(series) { item in
          VitalChart(series: item)
        }
      }
    }
  }

  struct VitalChart: View {

    let series: PatientDetailViewModel.VitalSeries

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(series.title)
            .font(.subheadline.weight(.medium))
          if !series.unitLabel.isEmpty {
            Text(series.unitLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Chart {
          referenceBand()

          ForEach(series.points) { point in
            LineMark(
              x: .value("Time", point.recordedAt),
              y: .value("Value", point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.tint)

            // 每個點的外觀完全相同——落在參考範圍外的點不做任何區別。
            // 帶子已經讓位置看得見；把某一點標成異常是判讀，不是呈現。
            PointMark(
              x: .value("Time", point.recordedAt),
              y: .value("Value", point.value)
            )
            .symbolSize(36)
            .foregroundStyle(.tint)
          }
        }
        .chartYScale(domain: series.valueRange)
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day().hour())
          }
        }
        .frame(height: 180)
      }
      .padding(20)
      .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    /// server 提供的參考範圍。
    ///
    /// 用中性灰而非紅或綠——顏色本身就是判讀。紅色在說「這裡不好」，
    /// 而那正是這個 app 不能說的話。帶子只陳述界限在哪裡。
    @ChartContentBuilder private func referenceBand() -> some ChartContent {
        // 上下界都有就畫成帶子，只有一邊就畫成虛線。
        // 沒有 else 分支：ReferenceBounds 至少有一邊才會被建出來。
        if let low = series.referenceRange?.low, let high = series.referenceRange?.high {
            RectangleMark(
                yStart: .value("Reference low", low),
                yEnd: .value("Reference high", high)
            )
            .foregroundStyle(.secondary.opacity(0.12))
        } else if let low = series.referenceRange?.low {
            RuleMark(y: .value("Reference low", low))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.4))
        } else if let high = series.referenceRange?.high {
            RuleMark(y: .value("Reference high", high))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.4))
        }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("有參考範圍與超出範圍的點") {
  let vm = PatientDetailViewModel(client: .preview, patient: .mock)
  vm.state.isFirstAppear = false
  vm.state.series = [.temperature, .oxygenSaturation]
  vm.state.api.loadVitals = .success
  return NavigationStack { PatientDetailView(viewModel: vm) }
}

#Preview("單一資料點") {
  let vm = PatientDetailViewModel(client: .preview, patient: .mock)
  vm.state.isFirstAppear = false
  vm.state.series = [.singlePoint]
  vm.state.api.loadVitals = .success
  return NavigationStack { PatientDetailView(viewModel: vm) }
}

#Preview("身分資料缺漏") {
  let vm = PatientDetailViewModel(client: .preview, patient: .sparse)
  vm.state.isFirstAppear = false
  vm.state.series = [.temperature]
  vm.state.api.loadVitals = .success
  return NavigationStack { PatientDetailView(viewModel: vm) }
}

#Preview("沒有紀錄") {
  let vm = PatientDetailViewModel(client: .preview, patient: .mock)
  vm.state.isFirstAppear = false
  vm.state.api.loadVitals = .success
  return NavigationStack { PatientDetailView(viewModel: vm) }
}

#Preview("有圖時刷新失敗") {
  let vm = PatientDetailViewModel(client: .preview, patient: .mock)
  vm.state.isFirstAppear = false
  vm.state.series = [.temperature]
  vm.state.api.loadVitals = .error(message: "Can't reach the server. Check the address and your connection.")
  return NavigationStack { PatientDetailView(viewModel: vm) }
}
#endif
