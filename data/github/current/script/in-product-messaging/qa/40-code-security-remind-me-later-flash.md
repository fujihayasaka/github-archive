# 40 — Code Security Risk Assessment "Remind me later" Flash (Team Org)

| Field | Value |
|-------|-------|
| **Login** | `ipm-code-security-team-flash` |
| **Test Page** | `/ipm-code-security-team-flash-org` |
| **Primary CTA** | "Scan now" → `/orgs/{org_slug}/security/assessments` |
| **Secondary CTA** | "Remind me later" |
| **Role** | Org admin of `ipm-code-security-team-flash-org` (Team plan) |
| **Setup** | Advanced Security purchased, no Copilot Business. Org is 60 days old with a 30-day-old repo. Feature flag `secure_ipm_security_risk_assessment_v2` enabled. Snooze for the "Remind me later" secondary CTA is reset on every setup run so the flash is re-testable. |

## Notes

- **Location:** Organization overview page — upsell banner rendered via `CodeSecurityRiskAssessmentBannerComponent`.
- **Banner title:** "Now scan for both secrets and vulnerabilities".
- This account exercises the **ephemeral "Remind me later" confirmation flash**. Clicking the secondary CTA does two things: (1) fires the existing 7-day snooze (dismiss POST), and (2) replaces the banner **in place** with a client-side info flash. The flash is pure frontend state — no notice record, no endpoint, gone on refresh.
- The flash props come from `secondary_action_flash` on the component and are passed through the `upsell-banner` React partial as `secondaryActionFlash`.
- Separate from accounts `29` (CTA/dismiss) so the snooze reset here does not perturb those fixtures.

## Expected flash content

| Field | Value |
|-------|-------|
| **Title** | "Reminder set for 7 days." |
| **Description** | "Reminder set for 7 days. Start a risk assessment anytime." |
| **Link text** | "risk assessment" (inline link within the description) |
| **Link destination** | `/orgs/{org_slug}/security/assessments` |
| **Link analytics action** | `remind_me_later_flash_link` |

## Checks

1. **Banner renders.** Visit `/ipm-code-security-team-flash-org` as `ipm-code-security-team-flash`. The upsell banner appears with primary CTA "Scan now" and secondary CTA "Remind me later".
2. **Flash appears on click.** Click "Remind me later". The banner is replaced in place by an info flash with the text "Reminder set for 7 days. Start a risk assessment anytime." on a single line (the title is visually hidden via `hideTitle`). No full-page navigation occurs.
3. **Inline link renders.** Within the flash description, "risk assessment" is a link pointing to `/orgs/ipm-code-security-team-flash-org/security/assessments`. (The link only renders because "risk assessment" is an exact substring of the description.)
4. **Link works + fires analytics.** Clicking the "risk assessment" link navigates to the assessments page and emits the `remind_me_later_flash_link` analytics action.
5. **Ephemeral.** Refresh the page. Because the secondary CTA recorded the 7-day snooze, the banner (and flash) are gone — the flash does not persist as its own state.
6. **Re-testable.** Re-run setup (or `script/in-product-messaging/setup --individual ipm-code-security-team-flash`). The snooze is reset and the banner renders again for another pass.
7. **X dismisses the flash.** The flash shows an X (close) button — required by ticket #240, criterion 3. Clicking it dismisses the flash in place. This affordance is the Primer `Banner` default `onDismiss`, handled on the `github-ui` side (`UpsellBanner.tsx`); no `github/github` code drives it.
