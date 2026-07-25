#if canImport(UIKit)
import UIKit

/// Colour overrides for the built-in player controls, loader, and message overlay.
///
/// All fields are optional — `nil` keeps the default appearance, so omitting any
/// field is backward-compatible.
///
/// ```swift
/// let style = BoomstreamPlayerStyle(
///     accentColor: UIColor(red: 0.4, green: 0.17, blue: 1, alpha: 1),  // #662BFF
///     loaderColor: .white
/// )
/// BoomstreamPlayerView(mediaCode: "...", style: style)
/// ```
public struct BoomstreamPlayerStyle: Sendable {
    /// Color of the spinner shown while the player is buffering.
    public var loaderColor: UIColor?
    /// Tint applied to the play/pause, seek, and navigation buttons.
    public var accentColor: UIColor?
    /// Fill color of the played (left) portion of the seek bar.
    /// Falls back to `accentColor` when `nil`.
    public var seekBarPlayedColor: UIColor?
    /// Color of the seek bar thumb (scrubber dot).
    /// Falls back to `accentColor` when `nil`.
    public var seekBarScrubberColor: UIColor?
    /// Fill color of the remaining (right) portion of the seek bar.
    public var seekBarBufferedColor: UIColor?
    /// Foreground color of the message/error label.
    public var messageTextColor: UIColor?
    /// Background color behind the message/error label. `nil` = no background.
    public var messageBackgroundColor: UIColor?

    public init(
        loaderColor: UIColor? = nil,
        accentColor: UIColor? = nil,
        seekBarPlayedColor: UIColor? = nil,
        seekBarScrubberColor: UIColor? = nil,
        seekBarBufferedColor: UIColor? = nil,
        messageTextColor: UIColor? = nil,
        messageBackgroundColor: UIColor? = nil
    ) {
        self.loaderColor = loaderColor
        self.accentColor = accentColor
        self.seekBarPlayedColor = seekBarPlayedColor
        self.seekBarScrubberColor = seekBarScrubberColor
        self.seekBarBufferedColor = seekBarBufferedColor
        self.messageTextColor = messageTextColor
        self.messageBackgroundColor = messageBackgroundColor
    }
}
#endif
