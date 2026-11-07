# Privacy in the recording build

LIFTR has no account service, backend, analytics SDK or cloud inference. Raw motion capture starts only when you intentionally begin recording on the Watch. This is research data collection, not an automatic exercise classifier.

The Watch records motion channels, recording labels, timestamps, a participant pseudonym, a session UUID, wrist, Watch model and watchOS version. Workout access supports the HealthKit workout lifecycle. The initial recording dataset does not need Apple Account identifiers, precise location, contacts or HealthKit exports.

WatchConnectivity transfers recording files to the paired iPhone. The apps store raw recordings separately from metadata summaries and phone review history. Export happens only through your chosen share-sheet destination. Choosing iCloud Drive, another cloud folder or a messaging app sends data there under that service's rules. Platform backups may also include local app data, depending on system settings.

Use a pseudonym for participant IDs. Do not commit raw datasets, exports, HealthKit exports, signing material or credentials. The repository's ignore rules reduce accidental inclusion but do not replace reviewing staged files.

You can delete saved recordings from the Watch recordings list or the iPhone detail screen. Watch deletion requires confirmation, warns about unsent motion, and cancels queued transfers where possible. Active recordings and drafts cannot be deleted through that saved-record action. That action deletes the phone copy and phone review history. It does not remove Watch copies, exports or backups. A Watch transfer retry may deliver that UUID again. Full coordinated retention and deletion across devices is a later reliability requirement, so manage source copies explicitly during research.

There is no automatic retention period in this build. Review storage regularly, export what you need, verify the export, and then delete copies you no longer want. Uninstalling an app may remove its local recordings. Never uninstall the only copy before checking a backup export.

Before TestFlight or App Store distribution, review actual data flows, retention controls, HealthKit usage, permission explanations and Apple's current privacy requirements. These notes describe the development build and are not an App Store privacy submission.

HealthKit workout records, if saved, are managed separately through Apple Health. No health data is sent to a LIFTR server.
