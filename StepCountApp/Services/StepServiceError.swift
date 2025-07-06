//
//  StepServiceError.swift
//  StepCountApp
//
//  Created by Jotaro Sugiyama on 2025/07/04.
//

import Foundation
import Combine

public enum StepServiceError: Error {
    case noProviderAvailable
    case permissionDenied
    case dataNotAvailable
}

public enum StepDataSource {
    case healthKit
    case coreMotion
    case hybrid
}

public struct StepData {
    public let steps: Int
    public let source: StepDataSource
    public let date: Date
    
    public init(steps: Int, source: StepDataSource, date: Date) {
        self.steps = steps
        self.source = source
        self.date = date
    }
}

/// 歩数データ取得サービスのプロトコル
///
/// HealthKitとCoreMotionを組み合わせて最適な歩数データを提供します。
public protocol StepServiceProtocol {
    /// HealthKitとCoreMotionの使用権限を要求します
    /// - Throws: StepServiceError 権限取得に失敗した場合
    func requestPermissions() async throws
    
    /// 今日の歩数を取得します
    /// - Returns: 今日の歩数データ
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchTodaySteps() async throws -> StepData
    
    /// 指定した期間の歩数を取得します
    ///
    /// 直近のデータについては、CoreMotionとHealthKitを比較したハイブリッドデータを返すことがあります。
    /// それより古いデータについては、HealthKitから取得します。
    /// - Parameters:
    ///   - startDate: 取得開始日時
    ///   - endDate: 取得終了日時
    /// - Returns: 取得した歩数データ
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> StepData
    
    /// 過去N日間の歩数を取得します
    /// - Parameter days: 取得する日数
    /// - Returns: 日付をキーとした歩数データの辞書
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchLastNDaysSteps(_ days: Int) async throws -> [Date: StepData]
    
    /// 特定の日付の歩数を取得します
    /// - Parameter date: 取得する日付
    /// - Returns: 指定日の歩数データ
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchStepsForSpecificDate(_ date: Date) async throws -> StepData
    
    /// 指定期間の日別歩数を取得します
    /// - Parameters:
    ///   - startDate: 開始日
    ///   - endDate: 終了日
    /// - Returns: 日付をキーとした歩数データの辞書
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: StepData]
    
    /// 指定月の歩数を取得します
    /// - Parameter date: 月を指定するための日付
    /// - Returns: 日付をキーとした歩数データの辞書
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchMonthlySteps(for date: Date) async throws -> [Date: StepData]
    
    /// 指定週の歩数を取得します
    /// - Parameter date: 週を指定するための日付
    /// - Returns: 日付をキーとした歩数データの辞書
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchWeeklySteps(for date: Date) async throws -> [Date: StepData]
    
    /// 指定年の歩数を取得します
    /// - Parameter year: 取得する年
    /// - Returns: 日付をキーとした歩数データの辞書
    /// - Throws: StepServiceError データ取得に失敗した場合
    func fetchYearlySteps(for year: Int) async throws -> [Date: StepData]
    
    /// リアルタイム歩数更新を開始します
    ///
    /// CoreMotionを使用してリアルタイムに歩数データを取得します。
    /// - Parameter handler: 歩数更新時に呼ばれるコールバック
    func startRealtimeStepUpdates(handler: @escaping (StepData) -> Void)
    
    /// リアルタイム歩数更新を停止します
    func stopRealtimeStepUpdates()
}

/// 歩数に関する各種機能を提供するサービス
///
/// HealthKitとCoreMotionをデータソースとして利用し、最適な歩数データを返します。
/// 直近のデータについてはハイブリッドアプローチを使用し、より古いデータについてはHealthKitから取得します。
@MainActor
public class StepService: StepServiceProtocol {
    
    /// StepServiceの動作設定
    public struct Configuration {
        /// CoreMotionとHealthKitのデータを比較するハイブリッドモードを使用するかどうか
        public let useHybridMode: Bool
        /// CoreMotionのデータ取得を試みる過去の日数
        public let coreMotionLookbackDays: Int
        
        /// デフォルト設定
        public static var `default`: Configuration {
            .init(useHybridMode: true, coreMotionLookbackDays: 7)
        }
        
        /// 設定のイニシャライザ
        /// - Parameters:
        ///   - useHybridMode: ハイブリッドモードを使用するかどうか
        ///   - coreMotionLookbackDays: CoreMotionでデータ取得を試みる過去の日数
        public init(useHybridMode: Bool, coreMotionLookbackDays: Int) {
            self.useHybridMode = useHybridMode
            self.coreMotionLookbackDays = coreMotionLookbackDays
        }
    }
    private let healthKitProvider: HealthKitStepProviding
    private let coreMotionProvider: CoreMotionStepProviding
    private let configuration: Configuration
    
    private var realtimeUpdateStartDate: Date?
    
    /// StepServiceのイニシャライザ
    /// - Parameters:
    ///   - healthKitProvider: HealthKit歩数データプロバイダー
    ///   - coreMotionProvider: CoreMotion歩数データプロバイダー
    ///   - configuration: サービスの動作設定
    public init(
        healthKitProvider: HealthKitStepProviding? = nil,
        coreMotionProvider: CoreMotionStepProviding? = nil,
        configuration: Configuration = .default
    ) {
        self.healthKitProvider = healthKitProvider ?? HealthKitStepProvider()
        self.coreMotionProvider = coreMotionProvider ?? CoreMotionStepProvider()
        self.configuration = configuration
    }
    
    public func requestPermissions() async throws {
        var errors: [Error] = []
        
        if healthKitProvider.isAvailable {
            do {
                try await healthKitProvider.requestPermission()
            } catch {
                errors.append(error)
            }
        }
        
        if coreMotionProvider.isAvailable {
            do {
                try await coreMotionProvider.requestPermission()
            } catch {
                errors.append(error)
            }
        }
        
        if !hasAnyProviderAvailable() {
            throw StepServiceError.noProviderAvailable
        }
    }
    
    public func fetchTodaySteps() async throws -> StepData {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        return try await fetchSteps(from: startDate, to: endDate)
    }
    
    public func fetchSteps(from startDate: Date, to endDate: Date) async throws -> StepData {
        let daysFromToday = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        
        if daysFromToday <= configuration.coreMotionLookbackDays && coreMotionProvider.isAvailable {
            if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
                return try await fetchHybridSteps(from: startDate, to: endDate)
            } else {
                let steps = try await coreMotionProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: steps, source: .coreMotion, date: endDate)
            }
        } else if healthKitProvider.isAvailable && healthKitProvider.isAuthorized {
            let steps = try await healthKitProvider.fetchSteps(from: startDate, to: endDate)
            return StepData(steps: steps, source: .healthKit, date: endDate)
        } else {
            throw StepServiceError.noProviderAvailable
        }
    }
    
    public func fetchLastNDaysSteps(_ days: Int) async throws -> [Date: StepData] {
        guard hasAnyProviderAvailable() else {
            throw StepServiceError.noProviderAvailable
        }
        
        let calendar = Calendar.current
        let endDate = Date()
        var result: [Date: StepData] = [:]
        
        for i in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: endDate)),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            
            do {
                let stepData = try await fetchSteps(from: dayStart, to: dayEnd)
                result[dayStart] = stepData
            } catch {
                continue
            }
        }
        
        return result
    }
    
    public func startRealtimeStepUpdates(handler: @escaping (StepData) -> Void) {
        guard coreMotionProvider.isAvailable else { return }
        
        let startDate = Date()
        realtimeUpdateStartDate = startDate
        
        coreMotionProvider.startRealtimeStepUpdates(from: startDate) { steps in
            let stepData = StepData(steps: steps, source: .coreMotion, date: Date())
            handler(stepData)
        }
    }
    
    public func stopRealtimeStepUpdates() {
        coreMotionProvider.stopRealtimeStepUpdates()
        realtimeUpdateStartDate = nil
    }
    
    private func fetchHybridSteps(from startDate: Date, to endDate: Date) async throws -> StepData {
        async let healthKitSteps = healthKitProvider.fetchSteps(from: startDate, to: endDate)
        async let coreMotionSteps = coreMotionProvider.fetchSteps(from: startDate, to: endDate)
        
        do {
            let (hkSteps, cmSteps) = try await (healthKitSteps, coreMotionSteps)
            
            let selectedSteps = max(hkSteps, cmSteps)
            
            return StepData(steps: selectedSteps, source: .hybrid, date: endDate)
        } catch {
            do {
                let hkSteps = try await healthKitProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: hkSteps, source: .healthKit, date: endDate)
            } catch {
                let cmSteps = try await coreMotionProvider.fetchSteps(from: startDate, to: endDate)
                return StepData(steps: cmSteps, source: .coreMotion, date: endDate)
            }
        }
    }
    
    public func fetchStepsForSpecificDate(_ date: Date) async throws -> StepData {
        let daysFromToday = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        
        // Check if HealthKit is available first
        guard healthKitProvider.isAvailable else {
            throw StepServiceError.noProviderAvailable
        }
        
        // For dates within configured lookback period, try hybrid approach
        if daysFromToday <= configuration.coreMotionLookbackDays && coreMotionProvider.isAvailable {
            do {
                // Try HealthKit first, then CoreMotion as fallback
                let steps = try await healthKitProvider.fetchStepsForSpecificDate(date)
                return StepData(steps: steps, source: .healthKit, date: date)
            } catch {
                // If HealthKit fails, try CoreMotion
                do {
                    let steps = try await coreMotionProvider.fetchStepsForSpecificDate(date)
                    return StepData(steps: steps, source: .coreMotion, date: date)
                } catch {
                    throw StepServiceError.dataNotAvailable
                }
            }
        } else {
            // For dates older than 7 days, use HealthKit only
            let steps = try await healthKitProvider.fetchStepsForSpecificDate(date)
            return StepData(steps: steps, source: .healthKit, date: date)
        }
    }
    
    public func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchStepsForDateRange(from: startDate, to: endDate)
        
        var result: [Date: StepData] = [:]
        for (date, steps) in healthKitSteps {
            result[date] = StepData(steps: steps, source: .healthKit, date: date)
        }
        
        return result
    }
    
    public func fetchMonthlySteps(for date: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchMonthlySteps(for: date)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    public func fetchWeeklySteps(for date: Date) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchWeeklySteps(for: date)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    public func fetchYearlySteps(for year: Int) async throws -> [Date: StepData] {
        guard healthKitProvider.isAvailable else {
            throw StepServiceError.noProviderAvailable
        }
        
        let healthKitSteps = try await healthKitProvider.fetchYearlySteps(for: year)
        
        var result: [Date: StepData] = [:]
        for (stepDate, steps) in healthKitSteps {
            result[stepDate] = StepData(steps: steps, source: .healthKit, date: stepDate)
        }
        
        return result
    }
    
    private func hasAnyProviderAvailable() -> Bool {
        return (healthKitProvider.isAvailable && healthKitProvider.isAuthorized) ||
        coreMotionProvider.isAvailable
    }
}
