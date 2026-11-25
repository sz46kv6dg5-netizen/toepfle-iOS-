import Foundation

public enum SharedConstants {
    public static let appGroupID = "group.de.toepfle.app"
    public static let queueFileName = "pending_imports.json"

    private static let keyDefaultServings = "toepfle_default_servings"
    private static let keyKeepScreenOn = "toepfle_keep_screen_on"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    public static var defaultServings: Int {
        get {
            let val = sharedDefaults?.integer(forKey: keyDefaultServings) ?? 0
            return val > 0 ? val : 4
        }
        set {
            sharedDefaults?.set(newValue, forKey: keyDefaultServings)
        }
    }

    public static var keepScreenOnDuringCooking: Bool {
        get {
            if sharedDefaults?.object(forKey: keyKeepScreenOn) == nil {
                return true
            }
            return sharedDefaults?.bool(forKey: keyKeepScreenOn) ?? true
        }
        set {
            sharedDefaults?.set(newValue, forKey: keyKeepScreenOn)
        }
    }
}
