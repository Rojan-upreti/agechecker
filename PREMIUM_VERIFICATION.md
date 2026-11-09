# Premium Identity Verification

## Implemented

- Base scanning remains the existing AVFoundation PDF417 + Vision OCR workflow.
- Premium adds explicit biometric consent, front/back ID capture, document review,
  Vision portrait extraction, a front-camera preview, sampled face/landmark/pose
  analysis, quality gates, randomized left/right temporal challenges, interruption
  tracking, bounded best-frame retention, and typed fail-closed decisions.
- Frame analysis runs off the main actor, samples every fourth delivered frame,
  drops late frames, permits only one inference in flight, and releases the capture
  session when the view exits.
- Raw facial images are kept in memory for the attempt. This implementation does
  not write them to disk, analytics, logs, or the photo library.

## Model selection status

No face-recognition or presentation-attack model is bundled.

ArcFace/InsightFace was evaluated as the leading embedding candidate. InsightFace
source code is MIT licensed, but its distributed pretrained model weights are
restricted to non-commercial research unless a separate commercial model license
is obtained. Therefore those weights were not copied into this commercial app.
Source: https://github.com/deepinsight/insightface

Silent-Face-Anti-Spoofing/MiniFASNet was evaluated for passive liveness. Its
repository is Apache-2.0, but it has not been integrated because the app team still
must validate weight provenance, Core ML conversion parity, performance on the
target devices, and PAD results against representative print, display, replay,
mask, synthetic, and injection attacks. Source:
https://github.com/minivision-ai/Silent-Face-Anti-Spoofing

The injectable `FaceEmbeddingProviding` and `LivenessDetecting` protocols return
unavailable in the production configuration. They never generate mock embeddings,
random scores, or automatic passes.

## Required model configuration

After commercial and privacy review:

1. Add licensed Core ML model assets to the application target.
2. Implement a provider for each protocol with identical face alignment and
   preprocessing for ID and live images.
3. Load each model once with `MLModelConfiguration.computeUnits = .all`.
4. Record immutable model identifiers, preprocessing version, and calibrated
   policy version with each result.
5. Calibrate thresholds on representative ID-to-self and ID-to-impostor data.
   Similarity is not a probability.
6. Validate PAD using ISO/IEC 30107-3 style APCER/BPCER reporting and attacks from
   every supported presentation-attack instrument class.

## Backend contract required for production

The current app has no backend. Local results are not authoritative and the
decision engine refuses to verify a locally created session.

A production backend must issue a short-lived session ID and cryptographic nonce,
bind attempts and uploaded evidence digests to that challenge, enforce attempt
limits and replay protection, validate all fields, and return a signed/server-held
final state. Use TLS with normal platform trust evaluation, authenticated requests,
least-privilege storage, encryption at rest, explicit retention/deletion policy,
and audit records that exclude raw biometrics and reusable embeddings.

## Device validation plan

Run on each supported front-camera class and OS version:

- matching person and ID; nonmatching person;
- printed portrait, another-phone display, replayed video, and mask;
- dark/backlit/overexposed scenes, blur, multiple faces, partial face, glasses,
  reasonable appearance changes, incomplete or reversed turns;
- camera denied, interrupted, backgrounded, unavailable, and thermal pressure;
- missing/corrupt model, cancellation, retry, expiration, replay, and attempt limit.

Measure false match rate and false non-match rate by demographic and capture
condition on a consented, representative evaluation set. Report PAD APCER/BPCER
per attack class, confidence intervals, failures-to-acquire, and the exact model,
threshold, device, and OS versions. Do not select a threshold from the test set.

## Production blockers

- Commercially licensed, converted, calibrated, and independently evaluated
  face-embedding model.
- Validated liveness/PAD model or reputable SDK with documented coverage.
- Server-issued challenge and server-controlled final decision.
- Legal/privacy review, retention controls, deletion APIs, and biometric consent
  language appropriate to every deployment jurisdiction.
- Physical-device security, accessibility, performance, and attack testing.

Until all blockers are complete, Premium ends in Verification Unavailable (or a
quality retry/manual-review state) and must not be marketed as fraud-resistant or
production-ready.
