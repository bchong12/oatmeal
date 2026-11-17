import CoreMedia
import Darwin

/// The one clock every track and event is stamped on: mach absolute time, as seconds.
/// ScreenCaptureKit sample times, NSEvent timestamps and CMClockGetHostTimeClock all count on it.
public enum HostClock {
    public static var clock: CMClock { CMClockGetHostTimeClock() }

    public static func now() -> CMTime { CMClockGetTime(clock) }

    public static var seconds: Double { now().seconds }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Mach ticks are not nanoseconds on Apple silicon (the timebase is 125/3), so always convert.
    public static func seconds(machTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}
