# Troubleshooting

## Xcode tools cannot find an SDK

Open full Xcode and install the required iOS/watchOS platforms. Run terminal scripts with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when the default points at CommandLineTools. Check `xcodebuild -version` with that variable. Do not change another Mac user's global settings to repair this project.

## XcodeGen is missing

Install XcodeGen and rerun `./scripts/bootstrap.sh`. The generated Xcode project comes from `project.yml`. Hand edits to generated project files may be replaced by the next generation.

## Signing or HealthKit provisioning fails

Choose your own team for both targets. Check unique companion bundle IDs, HealthKit capability and the actual team's profile in Xcode. Free provisioning can expire and may require running again from Xcode. Paid membership is needed for distribution. Do not remove HealthKit simply to make signing appear successful, since workout background behaviour depends on the intended capabilities.

## Watch app does not appear

Confirm the Watch is paired to the selected phone, supported by the deployment target, unlocked and in Developer Mode. Run `LIFTR` on the phone, then `LIFTRWatch` on the actual paired Watch. Give Xcode time to install platform support. Do not use simulator pairing to claim physical transfer works.

## Recording does not reach the phone

Check that both apps are installed and opened at least once. Background transfers are system scheduled and do not need the phone to be reachable at capture time. Keep both devices available, reopen the phone app, refresh the list and use retry on the Watch if offered. Preserve the Watch source copy while investigating. A queued status is not proof of arrival. Simulator does not support `transferFile`.

## Reps, weight or exercise label is wrong

Open the recording on iPhone and use its review action. It preserves the raw source and writes review history. Export again after correcting. A previously exported file does not update itself. Machine names may change later, but stable exercise IDs must survive.

## Schema validation fails

Run `python3 ml/validation/validate_recording.py path/to/file.liftr.json --json`. Read the named field. Do not repair timestamps by sorting or inventing samples before preserving the original file. Unknown versions need a compatible validator. A complete set without actual reps is not labelled training data. Invalid JSON may be an interrupted write; preserve it for recovery rather than treating it as a complete set.

## Sampling gaps or a lower rate appear

The target is 50 Hz, not a guarantee. Inspect gap warnings, screen-sleep behaviour, interruptions and actual sample rate on the Watch. Keep raw timestamps. Resampling belongs in reproducible later preprocessing, not an undocumented manual edit.

## Phone chart is slow or memory rises

The initial detail view decodes one raw recording before plotting a downsampled preview. Long continuous sessions need separate memory and battery tests. Start with short set recordings. Sharing unchanged files avoids decoding the full library, but exporting corrected recordings needs a decoded copy.

## A deleted recording comes back

Phone deletion removes only the phone copy and local review history. A Watch source retry may resend it. Coordinated deletion/tombstones are not established by that local delete action. Export and remove source copies deliberately during research.
