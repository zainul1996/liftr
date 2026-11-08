# Collecting gym data

This build collects labelled Apple Watch motion. It does not recognise exercises or count reps automatically. Enter what you actually performed.

## Before the gym

1. Install the apps on your paired iPhone and Apple Watch using [device setup](device-testing.md).
2. Open LIFTR on both devices once. Grant the Watch permissions requested when beginning a workout.
3. The Watch creates a persistent participant UUID automatically and reads the configured wrist from watchOS. Reinstalling the app can change that UUID; keep this in mind when grouping sessions.
4. Make a short test recording. Check it appears on the iPhone, then export and validate it before collecting a whole workout.

Do not record another person without their agreement. Raw motion and workout labels can reveal personal habits.

## Recording a set

1. Select the exact exercise on the Watch before starting the set.
2. Tap **Start Workout** for the first set. Individual-set mode immediately starts recording. During rest, tap **Start Set** for each later set.
3. Wait until the Watch shows recording has started, then perform your set normally.
4. Tap **End Set** after the last repetition.
5. Enter actual reps and weight in kilograms. If you are unsure, do not invent a number.
6. Save the set. The same exercise stays selected during rest for the next set.
7. Change the exercise when you change machines. Keep high-to-low, mid-height and low-to-high cable fly labels distinct.
8. End the workout when finished.

The leg-extension and seated-leg-curl names are provisional. Keep a note of the actual machine and its variant. Exercise IDs remain stable if display names are refined later.

If a recording fails or is interrupted, do not assume it was saved or transferred. Read the Watch status, retry if offered, and inspect the iPhone recording before including it in a dataset. A partial recovery file is not a successfully labelled set.

## Optional continuous capture

Before starting a workout, enable **Record rest too**. **Start Workout** begins continuous capture and shows the rest screen. Use **Start Set** and **End Set** to mark each exercise interval, then enter reps and weight and save its label. Raw capture continues during rest, machine changes and label entry. The selected exercise remains available for the next set.

Use **End Workout** to stop capture and save one session recording with set annotations. On iPhone, its detail screen lists labelled sets and previews motion across the session. Intervals outside the set annotations remain unlabelled context. If you do not know a set's label, leave that interval unlabelled rather than guessing.

Continuous capture has source implementation, but long-session battery, interruption recovery and actual sample rates still need physical Watch testing. Begin with a short trial and keep individual-set mode available. The first phone editor corrects individual-set recordings; editing separate annotations within a continuous session remains a later step. Machine-variant detail is currently strongest in individual-set mode.

## Review and export on iPhone

1. Open **Recordings**. Delivery may take time because WatchConnectivity schedules background files.
2. Open a set. Check the exercise, reps, weight, sample count, observed rate and gap count.
3. Use **Review exercise, reps and weight** to correct labels. The phone preserves original labels and a review history.
4. Use **Export recording**, or the share button on the recording list for all files.
5. Choose **Save to Files**. Export to a private directory you control.
6. On the Mac, run the validator described in [the schema](data-schema.md).

The waveform is a downsampled preview. The exported file preserves every raw sample. A smooth chart does not establish label accuracy.

Deleting a recording from the phone removes that phone copy and its phone review history. Watch copies, exported files and backups remain separate. A Watch retry may deliver a deleted phone recording again.

## Dataset targets after Run 1

Aim for 20 to 30 sets per supplied upper-body variation across several gym sessions, weights and tempos. Collect 15 sets each for seated leg extension and seated leg curl for the low-motion experiment. Do not rush extra repetitions just to hit a dataset target.

Rest, walking, machine adjustments, drinking water, carrying equipment, and holding handles without lifting are useful negative examples. Continuous-session recording and set-boundary marking need physical verification before relying on them for these negatives. Do not mark an ordinary negative motion as one of the exercise labels.

Keep session IDs intact. Later training must hold out whole recording sessions rather than splitting overlapping windows from the same session between training and testing.
