import Foundation

/// Адаптивный интервал синхронизации: если несколько циклов подряд ничего не менялось,
/// следующий цикл откладывается (меньше пробуждений). При любом изменении сети или маршрутов
/// интервал возвращается к базовому.
public enum SyncSchedule {
    public static let maxDelay = 300

    /// - Parameters:
    ///   - base: базовый интервал из настроек, секунды.
    ///   - unchanged: сколько циклов подряд маршруты не менялись.
    ///   - hasApps: есть ли приложения в списке (их соединения меняются чаще, поэтому растяжение меньше).
    public static func delay(base: Int, unchanged: Int, hasApps: Bool) -> Int {
        let factor = unchanged >= 6 ? (hasApps ? 2 : 4) : unchanged >= 3 ? 2 : 1
        return max(base, min(base * factor, maxDelay))
    }
}
