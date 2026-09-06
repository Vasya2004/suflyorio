import AVFoundation
import Foundation

public enum MovieValidation {
    /// A completion callback is not proof of a usable recording (e.g. full disk).
    /// Validate a file without loading its media data into memory.
    public static func playableDuration(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let playable = try await asset.load(.isPlayable)
            guard playable, duration.isFinite, duration > 0, !video.isEmpty, !audio.isEmpty else { return nil }
            return duration
        } catch { return nil }
    }
}
