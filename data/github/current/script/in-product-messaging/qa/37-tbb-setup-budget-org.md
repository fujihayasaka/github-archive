# 37 — TBB Setup Budget Banner (Team Org)

| Field | Value |
|-------|-------|
| **CTA Login** | `ipm-tbb-setup-budget-team` |
| **Dismiss Login** | `ipm-tbb-setup-budget-team-dismiss` |
| **Test Page** | `/ipm-tbb-setup-budget-team-org` |
| **Test Page (Dismiss)** | `/ipm-tbb-setup-budget-team-dismiss-org` |
| **Expected CTA** | "Set your budget" |
| **Expected Destination** | `/organizations/{org_slug}/settings/billing/budgets/new?budget_type=premium_requests&budget_scope=multi_user_customer` |
| **Dismiss Type** | Standard — dismiss button on the banner |
| **Role** | Org admin of a Team org with Copilot Business enabled |
| **Setup** | Team org with Copilot Business. Feature flags `general_ipm_tbb_setup_budget`, `billing_user_level_budgets`, `billing_user_level_budgets_manage` enabled. No existing Copilot multi-user budget. |

## Notes

- **Location:** Organization overview page — banner rendered via `TbbSetupBudgetBannerComponent` in `app/views/orgs/_index_header.html.erb`.
- **Banner text:** Prompts org admins to set up a per-user Copilot premium request budget.
- **Issue:** [github/in-product-messaging#473](https://github.com/github/in-product-messaging/issues/473)
- **Nudge ID:** `general_ipm_tbb_setup_budget`
- **Component:** `InProductTargeting::Components::OrganizationBanners::TbbSetupBudgetBannerComponent`
- **CTA account** (`ipm-tbb-setup-budget-team`): Use for Checks 1–4. Test page: `/ipm-tbb-setup-budget-team-org`.
- **Dismiss account** (`ipm-tbb-setup-budget-team-dismiss`): Use for Checks 5–6. Test page: `/ipm-tbb-setup-budget-team-dismiss-org`. Identical setup — separate org so dismiss state doesn't affect CTA tests.
- **Eligibility:**
  1. User must have `general_ipm_tbb_setup_budget` feature flag enabled.
  2. User must be an org admin or billing manager.
  3. Org must have `billing_user_level_budgets` and `billing_user_level_budgets_manage` flags enabled.
  4. No existing Copilot multi-user budget on the org.
  5. User has not dismissed the notice.
  6. User is subscribed to in-product messages.
