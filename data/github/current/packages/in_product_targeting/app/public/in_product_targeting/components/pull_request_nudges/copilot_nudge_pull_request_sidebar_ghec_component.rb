# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module PullRequestNudges
      class CopilotNudgePullRequestSidebarGhecComponent < PullRequestIpmSidebarNudgeBaseComponent
        NUDGE_CATEGORY = "pr_show_ccr_ghec_owner_primary_nudge"
        NUDGE_ID = :pr_show_ccr_ghec_owner_primary_nudge

        private

        sig { override.returns(String) }
        def nudge_category = NUDGE_CATEGORY

        sig { override.returns(Symbol) }
        def nudge_id = NUDGE_ID

        sig { override.returns(String) }
        def nudge_title = "You're missing out on AI-powered reviews"

        sig { override.returns(String) }
        def nudge_description = "Enable Copilot code review to spot issues early and speed up reviews."

        sig { override.returns(String) }
        def nudge_cta = "Enable Copilot code review"

        sig { override.returns(String) }
        def nudge_cta_action = "get_started"

        sig { override.returns(String) }
        def nudge_image_path_dark = "modules/pulls/promos/copilot_nudge-dark.png"

        sig { override.returns(String) }
        def nudge_image_path_light = "modules/pulls/promos/copilot_nudge-light.png"

        sig { override.returns(String) }
        def nudge_image_alt_dark = "Dark Copilot Code Review Background"

        sig { override.returns(String) }
        def nudge_image_alt_light = "Light Copilot Code Review Background"

        sig { override.returns(T::Boolean) }
        def eligible_for_nudge?
          return false unless base_eligibility_checks_are_satisfied?
          return false unless org_copilot.has_copilot_for_business?
          return false if org_copilot.code_review_enabled?
          return false unless business
          return false unless T.must(business).owner?(current_user)

          true
        end

        sig { returns(T.nilable(Business)) }
        memoize def business
          organization.business
        end

        sig { returns(String) }
        def enterprise_slug
          business&.slug || ""
        end

        sig { override.returns(String) }
        def nudge_cta_href
          agents_policy_enterprise_ai_controls_enterprise_path(enterprise_slug)
        end
      end
    end
  end
end
