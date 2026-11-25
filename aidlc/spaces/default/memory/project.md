# Project-Level Rules

> Project-specific specialisation and corrections. Loaded after `org.md` and
> `team.md` as strict-additive guidance.
> Populated by practices-discovery and the self-learning loop.
>
> Use sparingly: most teams don't need a project layer. Reach for it
> only when this specific project needs stable, durable guidance beyond the
> team practice (for example, package-specific release checks or an additional
> regression suite for a legacy component).

## Way of Working

<!-- Project-specific specialisation. Example: -->
<!-- This monorepo requires package-scoped branch names and a package owner -->
<!-- review in addition to the team's normal merge policy. -->
<!-- A project that merges into another branch than team.md names says so on its own line, read before team.md's: -->
<!-- - **Integration branch**: develop -->

- This is an idea-first demo/prototype project. The goal is a working, demonstrable Demo that delivers the Owner-approved requirements correctly. Finishing the Demo outranks process polish.
- Remove blockers: choose a reasonable default and record it as an assumption instead of stopping to ask. Ask the Owner only when a business-scope decision is truly undecidable from `docs/product/requirements.md`.
- Avoid ping-pong: batch questions into one round, do not re-ask anything already decided, do not loop between reviewers and authors more than one revision pass, and prefer advisory over blocking reviews.
- Prefer the lightest scope and depth that still produces a correct Demo (mvp or express). Skip stages that do not change the Demo output.
- Judge output by correctness against the requirements and acceptance criteria, not by production-grade hardening.

## Walking Skeleton

<!-- Project-specific specialisation. Example: -->
<!-- The walking skeleton must exercise the legacy service adapter as well -->
<!-- as the new service boundary. -->

## Testing Posture

<!-- Project-specific specialisation. -->

- Test the Demo flows against the requirements: profile -> AI result -> sourced opportunity -> action plan -> progress, plus the negative cases in the acceptance criteria. Do not add hardening, load, or security test suites.

## Guard Policy

<!-- Project-specific. Mode: strict, relaxed, or off. Strict here holds for every intent, whatever one person asks in chat; relaxed or off here applies to every intent whose policy came from its scope, unless the person sets another; changing this line changes it. A section under the retired Change Control heading, written by an earlier release, is still read. -->

Mode: off

The Owner chose speed to a working Demo over process guards (requested in chat).

## Deployment

<!-- Project-specific specialisation. -->

- Demo only: an installable Android build (or equivalent runnable Demo) is enough. No production deployment, store publishing, or environment hardening.

## Code Style

<!-- Project-specific specialisation. -->

- Prefer simple, readable code that works over abstraction. Do not spend effort on performance tuning, auth, encryption, rate limiting, or other production security for the Demo.

## Tech Stack

<!-- Technology choices locked for this project. -->

- Mobile framework: Flutter (Dart), Android first. iOS may be added later from the same codebase but is out of scope for the Demo. Chosen by the Owner. AI provider, backend, hosting, and persistence remain open for AI-DLC design.

## Decided

<!-- Decisions made in earlier stages that should not be re-asked. -->
<!-- Format: DECIDED: [decision] (Stage [slug], [date]) -->

DECIDED: Use Flutter for the mobile app; do not re-compare frameworks in design. (Owner decision in chat)

## Scope Overrides

<!-- Custom scope rules for this project. -->

## Forbidden

<!-- Populated by practices-discovery affirmation gate. -->
<!-- Format: - NEVER [behavior] (affirmed [date]) -->
<!-- Example: - NEVER throw exceptions across service layer boundaries (affirmed 2026-05-17) -->

- NEVER present mock eligibility, payment, employment, or government data as a verified live result; label it DEMO / MOCK.
- NEVER guarantee money, benefits, jobs, or income from AI output.
- NEVER commit real secrets or real personal data to the repository, because it is public on GitHub.

## Mandated

<!-- Populated by practices-discovery affirmation gate. -->
<!-- Format: - ALWAYS [behavior] (affirmed [date]) -->
<!-- Example: - ALWAYS use Result<T,E> for fallible operations in service layer (affirmed 2026-05-17) -->

- ALWAYS deliver output that matches `docs/product/requirements.md` and its acceptance criteria.
- ALWAYS distinguish sourced facts, estimates, AI inferences, user-reported progress, and mock data.
- ALWAYS use synthetic user identities in the Demo.
- ALWAYS finish a runnable Demo end to end before adding extras.

## Corrections

<!-- Project-specific corrections from human feedback. -->
<!-- Format: NEVER/ALWAYS [behavior] (learned [date]) -->
