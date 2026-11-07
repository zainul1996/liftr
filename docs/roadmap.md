# Delivery roadmap

## Run 1

Deliver labelled Apple Watch recording through local persistence, iPhone transfer, review and export. Validate the JSON contract and native application builds. Use real device checks before collecting the full dataset. Optional continuous collection must preserve sample timestamps and set annotations while keeping memory bounded.

## Run 2

Validate actual Apple Watch data and collect specific missing examples. Split by recording session. Compare feature-based and lightweight CNN models, flat and hierarchical recognition, confidence handling, unknown rejection, signal-based rep counting and deterministic set detection. Convert only a measured compatible model to Core ML. Keep assisted/manual fallback.

## Run 3

Use a separate feedback dataset to improve confusion pairs, counting and set boundaries. Preserve untouched evaluation data. Finish history, analytics, weight tracking, privacy, battery checks and an approved beta process. A tested recording app does not establish recognition accuracy or commercial readiness.
