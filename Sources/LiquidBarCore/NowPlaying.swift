import Foundation

public struct NowPlaying: Equatable, Sendable {
    public enum Player: String, Sendable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        /// The AppleScript application name.
        public var appName: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }
    }

    public var player: Player
    public var title: String
    public var artist: String
    /// Spotify's "spotify:track:…" URI, or Music's persistent ID.
    public var trackID: String
    public var playing: Bool

    public init(player: Player, title: String, artist: String, trackID: String, playing: Bool) {
        self.player = player
        self.title = title
        self.artist = artist
        self.trackID = trackID
        self.playing = playing
    }
}

/// Reads the userInfo of `com.spotify.client.PlaybackStateChanged` or `com.apple.Music.playerInfo`.
/// Returns nil when the player stopped or the notification carries no track.
public func parseNowPlaying(_ info: [AnyHashable: Any], player: NowPlaying.Player) -> NowPlaying? {
    guard let state = info["Player State"] as? String, state == "Playing" || state == "Paused",
          let title = info["Name"] as? String, !title.isEmpty
    else { return nil }
    let id = info[player == .spotify ? "Track ID" : "PersistentID"].map { "\($0)" } ?? title
    return NowPlaying(player: player, title: title, artist: info["Artist"] as? String ?? "", trackID: id, playing: state == "Playing")
}

/// The Spotify track ID from a "spotify:track:<id>" URI, for the oEmbed artwork lookup.
public func spotifyTrackID(_ uri: String) -> String? {
    let parts = uri.split(separator: ":")
    guard parts.count == 3, parts[0] == "spotify", parts[1] == "track" else { return nil }
    return String(parts[2])
}
