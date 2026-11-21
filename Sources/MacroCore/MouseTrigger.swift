import Foundation

/// Rules for using a mouse button (CGEvent `buttonNumber`) as a global trigger.
/// Left (0) and right (1) are never allowed: consuming them would make the mouse unusable.
public enum MouseTrigger {
    public static func isAllowed(_ button: Int) -> Bool { (2..<32).contains(button) }

    /// Whether a mouse event should be consumed as the trigger; macrecord's own synthetic clicks pass through.
    public static func matches(buttonNumber: Int64, userData: Int64, trigger: Int) -> Bool {
        isAllowed(trigger) && buttonNumber == Int64(trigger) && userData != macrecordEventTag
    }
}
