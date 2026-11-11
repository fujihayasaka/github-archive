# 30 — Code Security Risk Assessment (GHEC)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-code-security-ghec-owner` |
| **Dismiss Login** | `ipm-code-security-ghec-dismiss` |
| **Test Page** | `/ipm-code-security-ghec-org` |
| **Test Page (Dismiss)** | `/ipm-code-security-ghec-dismiss-org` |
| **Expected CTA** | "Scan now" |
| **Expected Destination** | `/orgs/{org_slug}/security/assessments` |
| **Dismiss Type** | Standard — dismiss button on the upsell banner |
| **Role** | Enterprise owner of `ipm-code-security-ghec-biz`, org is `ipm-code-security-ghec-org` (Enterprise Cloud plan) |
| **Setup** | Advanced Security purchased, no Copilot Business. Enterprise is 60 days old, org is 30 days old with a 30-day-old repo. Feature flag `secure_ipm_security_risk_assessment_v2` enabled. |

## Notes

- **Location:** Organization overview page — upsell banner rendered via `CodeSecurityRiskAssessmentBannerComponent`
- **Banner title:** "Now scan for both secrets and vulnerabilities"
- The banner uses the shared `upsell-banner` React partial with a dismiss button
- This is the **Enterprise Cloud** variant — only the enterprise account owner sees the banner
- **CTA account** (`ipm-code-security-ghec-owner`): Use for Checks 1–4. Test page: `/ipm-code-security-ghec-org`
- **Dismiss account** (`ipm-code-security-ghec-dismiss`): Use for Checks 5–6. Test page: `/ipm-code-security-ghec-dismiss-org`. Identical setup — separate enterprise `ipm-code-security-ghec-dismiss-biz` with org `ipm-code-security-ghec-dismiss-org`.
