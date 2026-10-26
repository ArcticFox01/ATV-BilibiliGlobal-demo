# Subtitle playback handoff — 2026-10-26

## Summary

English and Thai subtitle tracks were selectable in tvOS but did not render. Indonesian rendered. The confirmed fix is commit `b6b5bcc`, which emits ASS-derived WebVTT cues in chronological order without changing any source timestamp. The user verified that the tracks work after deployment to AppleTV Sim.

## Symptom

- AVKit displayed English, Thai, and Indonesian as legible media options.
- Selecting English or Thai produced repeated CoreMedia errors: `WebVTTSamples signalled err=-16012 at <>:1157`.
- Indonesian did not produce that error and rendered.

## Root cause

`WebRequest.decodeASSSubtitles(_:)` correctly extracted each ASS `Dialogue:` start and end time, but retained the original file order. `BVideoUrlUtils.convertToVTT(subtitle:)` emitted that order unchanged into one HLS WebVTT segment.

The English and Thai ASS files place styled screen-title cues at later timestamps before earlier dialogue cues. For example, English has title cues around 21 minutes and later returns to dialogue at 3 seconds; Thai has the same pattern. Indonesian arrives chronologically. AVFoundation rejects the resulting non-monotonic WebVTT samples with `-16012`.

## Fix

- `3c07228` simplified generated WebVTT cues and removed cue-position syntax. This did not resolve the language-specific parser error.
- `ec40de5` added the required HLS `X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0`. This made the generated subtitle segment HLS-compliant, but did not correct out-of-order ASS input.
- `b6b5bcc` stably sorts decoded cues by existing `from`, `to`, then original index before VTT emission. It preserves all source timestamps and concurrent/overlapping cues.

## Validation

- Reproduced on AppleTV Sim with an episode exposing English, Thai, and Indonesian ASS tracks.
- Confirmed fresh logs: English and Thai emitted `WebVTTSamples -16012`; Indonesian did not.
- `xcodebuild` simulator build succeeded after `b6b5bcc`.
- User confirmed English/Thai playback works after the deployed build.

## Why it slipped through

There is no automated subtitle conversion or AVFoundation playback test. Prior checks confirmed that cues loaded and tracks were selectable, but did not compare chronological ordering across real ASS language files.

## Handoff notes

- Subtitle conversion and the local HLS route are in `BiliBiliGlobal/Component/Player/BilibiliVideoResourceLoaderDelegate.swift`.
- ASS decoding is in `BiliBiliGlobal/Request/WebRequest.swift`.
- Preserve the HLS timestamp map and chronological ordering invariant for every subtitle source.
- The previous per-user subtitle vertical-position setting is currently not emitted in the strict WebVTT cue format. Restore it only with an HLS/WebVTT form confirmed by AVFoundation; do not reintroduce the old cue setting blindly.
- Recommended follow-up: add fixture-based conversion tests for out-of-order ASS title/dialogue cues when a Swift test target is introduced.
