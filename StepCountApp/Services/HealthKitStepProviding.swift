import Foundation

/// HealthKitを使用した歩数データ取得機能を提供するプロトコル
public protocol HealthKitStepProviding {
    /// HealthKitが利用可能かどうか
    var isAvailable: Bool { get }
    
    /// HealthKitへのアクセスが許可されているかどうか
    var isAuthorized: Bool { get }
    
    /// HealthKitへのアクセス権限を要求する
    /// - Throws: HealthKitStepError
    func requestPermission() async throws
    
    /// 今日の歩数を取得する
    /// - Returns: 今日の歩数
    /// - Throws: HealthKitStepError
    func fetchTodaySteps() async throws -> Int
    
    /// 指定期間の歩数を取得する
    /// - Parameters:
    ///   - startDate: 開始日時
    ///   - endDate: 終了日時
    /// - Returns: 指定期間の歩数
    /// - Throws: HealthKitStepError
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int
    
    /// 過去N日間の歩数を取得する
    /// - Parameter days: 取得する日数
    /// - Returns: 日付をキーとした歩数の辞書
    /// - Throws: HealthKitStepError
    func fetchStepsForLastNDays(_ days: Int) async throws -> [Date: Int]
    
    /// 特定の日付の歩数を取得する
    /// - Parameter date: 取得する日付
    /// - Returns: 指定日の歩数
    /// - Throws: HealthKitStepError
    func fetchStepsForSpecificDate(_ date: Date) async throws -> Int
    
    /// 指定期間の日別歩数を取得する
    /// - Parameters:
    ///   - startDate: 開始日
    ///   - endDate: 終了日
    /// - Returns: 日付をキーとした歩数の辞書
    /// - Throws: HealthKitStepError
    func fetchStepsForDateRange(from startDate: Date, to endDate: Date) async throws -> [Date: Int]
    
    /// 指定月の歩数を取得する
    /// - Parameter date: 月を指定するための日付
    /// - Returns: 日付をキーとした歩数の辞書
    /// - Throws: HealthKitStepError
    func fetchMonthlySteps(for date: Date) async throws -> [Date: Int]
    
    /// 指定週の歩数を取得する
    /// - Parameter date: 週を指定するための日付
    /// - Returns: 日付をキーとした歩数の辞書
    /// - Throws: HealthKitStepError
    func fetchWeeklySteps(for date: Date) async throws -> [Date: Int]
    
    /// 指定年の歩数を取得する
    /// - Parameter year: 取得する年
    /// - Returns: 日付をキーとした歩数の辞書
    /// - Throws: HealthKitStepError
    func fetchYearlySteps(for year: Int) async throws -> [Date: Int]
}