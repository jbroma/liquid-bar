import LiquidBarCore
import Testing

@Test func parsesSpotifyPlaybackNotification() {
    let info: [AnyHashable: Any] = [
        "Player State": "Playing", "Name": "Windowlicker", "Artist": "Aphex Twin", "Album": "Windowlicker",
        "Track ID": "spotify:track:1R2SZUOGJqqBiLuvwKOT2Y", "Duration": 367_000, "Playback Position": 12.5,
    ]
    #expect(parseNowPlaying(info, player: .spotify) == NowPlaying(
        player: .spotify, title: "Windowlicker", artist: "Aphex Twin", trackID: "spotify:track:1R2SZUOGJqqBiLuvwKOT2Y", playing: true))
    var paused = info
    paused["Player State"] = "Paused"
    #expect(parseNowPlaying(paused, player: .spotify)?.playing == false)
    #expect(parseNowPlaying(["Player State": "Stopped", "Track ID": ""], player: .spotify) == nil)
    #expect(parseNowPlaying(["Player State": "Playing"], player: .spotify) == nil)
}

@Test func parsesMusicPlayerInfoNotification() {
    let info: [AnyHashable: Any] = ["Player State": "Paused", "Name": "Teardrop", "Artist": "Massive Attack", "PersistentID": 4_242_424_242]
    #expect(parseNowPlaying(info, player: .music) == NowPlaying(
        player: .music, title: "Teardrop", artist: "Massive Attack", trackID: "4242424242", playing: false))
}

@Test func extractsSpotifyTrackID() {
    #expect(spotifyTrackID("spotify:track:1R2SZUOGJqqBiLuvwKOT2Y") == "1R2SZUOGJqqBiLuvwKOT2Y")
    #expect(spotifyTrackID("spotify:episode:abc") == nil)
    #expect(spotifyTrackID("") == nil)
}
