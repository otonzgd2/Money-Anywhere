# Money Anywhere — Product Requirements

**Version:** v0.1  
**Status:** Owner-approved business brief (2026-11-20); technical design pending AI-DLC.  
**Role:** Source input for Kiro/AWS AI-DLC, not an AI-DLC-generated stage artifact.

## 1. Objective and intended outcome

Build an Android-first mobile app helping people discover legitimate money they may be entitled to receive or recover, and ways to generate income. Turn relevant opportunities into personalized, evidence-backed plans and help users track their actions.

**Product promise:** Find and act on legitimate opportunities. Do not promise guaranteed money, eligibility, employment, or payment.

## 2. Target users

The general public, with emphasis on people with low income, unemployed people, older adults, and those seeking additional income.

## 3. Opportunity coverage

Design for these ten categories, without committing to full MVP integrations for all of them:

1. Government welfare and benefits.
2. Refunds, e.g., taxes, deposits, and overpayments.
3. Money owed, e.g., wages, compensation, and claims.
4. Full-time jobs.
5. Part-time, daily, and temporary jobs.
6. Freelance and contract work.
7. Selling goods, secondhand items, or personal property.
8. Lawful income from existing assets.
9. Grants and non-repayable assistance.
10. Earning opportunities enabled by new or existing skills.

Loans and credit are debts, not income. Non-cash entitlements must not be presented as withdrawable cash.

## 4. Functional requirements

- **FR-01 — AI Profile:** Understand user circumstances, skills, location, available time, constraints, and income goals while collecting only necessary data.
- **FR-02 — Opportunity Matching:** Find and prioritize relevant options, explain why they match, and identify missing information.
- **FR-03 — Evidence:** For each opportunity, show its identifiable source, verification/freshness status, conditions, uncertainty, and next steps.
- **FR-04 — Income Planner:** Compare possible earnings, direct costs, estimated net income, effort, time to payment, and risks; mark estimates and assumptions.
- **FR-05 — Action Assistant:** Provide checklists, document preparation guidance, and links or handoffs to official or verified providers. Do not automatically apply or transact without authorized integration.
- **FR-06 — Money Tracker:** Track actions and outcomes, clearly distinguishing user-reported stages from externally verified status.
- **FR-07 — Scam Signals:** Flag potential fraud patterns such as advance fees and requests for sensitive credentials, without promising perfect fraud detection.
- **FR-08 — Failure Handling:** Handle insufficient details, no matching opportunities, stale or contradictory data, missing API access, and AI failures without fabricating results.

## 5. Competition MVP

Implement real end-to-end flows for three groups, using a small, source-attributed reference set and explicitly labeled mock adapters only where necessary:

- **A — Money to check or recover:** Selected welfare, refunds, or outstanding payments.
- **B — Employment:** Appropriate full-time, short-term, or part-time opportunities.
- **C — Skill-based income:** Realistic income ideas from existing skills, including effort and cost assumptions.

MVP includes profile intake, meaningful live AI analysis/matching/planning, opportunity evidence, an actionable checklist in each track, and user-managed progress. It must not be merely a collection of links or hard-coded demonstration screens. Other opportunity categories are deferred implementation, not missing model scope.

## 6. Data and trust boundaries

- Government agencies and service providers remain authoritative for personal eligibility, official application status, live vacancies, and payment outcomes. Do not imply private government-data access.
- Clearly label all fabricated profiles, simulated service records, synthetic payments, and mock APIs as **DEMO / MOCK**, including during the competition pitch.
- Distinguish sourced facts, AI inference, user-reported facts, estimates, and unknowns. Never invent source references, benefits, vacancies, or payout amounts.
- Prefer versioned, testable business rules and deterministic calculations for eligibility checks and arithmetic; AI supports understanding, matching, and explanations.
- Minimize personal data and use synthetic profiles in demonstrations; never commit credentials or sensitive personal records.
- Give users an identified official/provider channel for authoritative verification and action.

## 7. Team, packaging, and delivery

- Three human contributors using the repository's existing Kiro/AWS AI-DLC workflow, shared interfaces, and independently verifiable Units of Work.
- Android-installable mobile app, functioning AI/backend flow, accessible source code, demonstrated end-to-end experience, and test evidence.
- Establish a repeatable Android packaging/install path early. Preserve a known-good integrated build and tie verification evidence to the exact source revision.
- Competition assets: pitch deck of **fewer than 8 slides**, live demo, and backup video **under 3 minutes**.
- Do not predetermine mobile framework, backend provider, AI model, hosting, or persistence before the appropriate AI-DLC design decision.

## 8. Acceptance criteria

- **AC-01:** At least three synthetic user scenarios (one per MVP track) complete profile -> meaningful AI result -> source/assumptions -> next-action checklist -> progress record on an installed device.
- **AC-02:** Live AI is actually invoked; simulated data and mock API responses are clearly identified.
- **AC-03:** No output promises or falsely verifies guaranteed benefits, payments, official eligibility, or jobs.
- **AC-04:** Negative cases cover missing profile information, no results, suspicious opportunities, stale/invalid sources, and downstream/AI failure.
- **AC-05:** Build, test, Android installation, and live end-to-end demonstration have evidence attached to an exact commit.
- **AC-06:** Three people can develop their own units, integrate by shared contracts, and ship one tested application.
- **AC-07:** Differentiation from existing services is an outcome hypothesis until tested with people and comparable alternatives.

## 9. Deferred

Production identity verification, personal governmental entitlement database integration, automatic external applications, money transfer, app-store publishing, and full live integrations across all ten opportunity categories.

## 10. AI-DLC handoff

This document captures approved business intent. Let the existing AI-DLC process conduct inception, requirements elaboration, design, delivery planning, risk evaluation, and Owner checkpoints. Do not manually create AI-DLC intent state, reviews, or stage files. Escalate proposed changes to product scope, eligibility guarantees, privacy/trust boundaries, costs, access rights, or publication/deployment.
