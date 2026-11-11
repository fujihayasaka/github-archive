# 29 — Code Security Risk Assessment (Team Org)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-code-security-team-admin` |
| **Dismiss Login** | `ipm-code-security-team-dismiss` |
| **Test Page** | `/ipm-code-security-team-org` |
| **Test Page (Dismiss)** | `/ipm-code-security-team-dismiss-org` |
| **Expected CTA** | "Scan now" |
| **Expected Destination** | `/orgs/{org_slug}/security/assessments` |
| **Dismiss Type** | Standard — dismiss button on the upsell banner |
| **Role** | Org admin of `ipm-code-security-team-org` (Team plan) |
| **Setup** | Advanced Security purchased, no Copilot Business. Org is 60 days old with a 30-day-old repo. Feature flag `secure_ipm_security_risk_assessment_v2` enabled. |

## Notes

- **Location:** Organization overview page — upsell banner rendered via `CodeSecurityRiskAssessmentBannerComponent`
- **Banner title:** "Now scan for both secrets and vulnerabilities"
- The banner uses the shared `upsell-banner` React partial with a dismiss button
- This is the **Team plan org admin** variant — the admin sees the banner because they are an org admin with Advanced Security purchased
- **CTA account** (`ipm-code-security-team-admin`): Use for Checks 1–4. Test page: `/ipm-code-security-team-org`
- **Dismiss account** (`ipm-code-security-team-dismiss`): Use for Checks 5–6. Test page: `/ipm-code-security-team-dismiss-org`. Identical setup — separate org `ipm-code-security-team-dismiss-org`.
