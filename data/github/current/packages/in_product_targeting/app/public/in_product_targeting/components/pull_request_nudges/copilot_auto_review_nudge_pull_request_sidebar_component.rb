# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module PullRequestNudges
      class CopilotAutoReviewNudgePullRequestSidebarComponent < PullRequestIpmSidebarNudgeBaseComponent
        NUDGE_CATEGORY = "accelerate_ipm_automatic_ccr_nudge_on_pull_requests"
        NUDGE_ID = :accelerate_ipm_automatic_ccr_nudge_on_pull_requests
        FEATURE_FLAG = :copilot_auto_review_nudge_pull_request_sidebar

        private

        sig { override.returns(String) }
        def nudge_category = NUDGE_CATEGORY

        sig { override.returns(Symbol) }
        def nudge_id = NUDGE_ID

        sig { override.returns(String) }
        def nudge_title = "Your PRs aren’t being reviewed automatically"

        sig { override.returns(String) }
        def nudge_description = "Automatically review every PR with Copilot to ship higher-quality code."

        sig { override.returns(String) }
        def nudge_cta = "Enable automatic code review"

        sig { override.returns(String) }
        def nudge_cta_action = "enable_auto_review"

        sig { override.returns(String) }
        def nudge_image_path_dark = "modules/pulls/promos/copilot_auto_review_nudge-dark.png"

        sig { override.returns(String) }
        def nudge_image_path_light = "modules/pulls/promos/copilot_auto_review_nudge-light.png"

        sig { override.returns(String) }
        def nudge_image_alt_dark = "Dark Copilot Code Review Background"

        sig { override.returns(String) }
        def nudge_image_alt_light = "Light Copilot Code Review Background"

        sig { override.returns(T::Boolean) }
        def eligible_for_nudge?
          return false unless current_user.feature_flag_enabled?(FEATURE_FLAG, default: false)
          return false unless current_user.subscribed_to_in_product_messages?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || current_user.is_enterprise_managed?
          return false unless repository.owner.is_a?(Organization)
          return false if organization.feature_flag_enabled?(:disable_copilot_auto_review_nudge_pull_request_sidebar, default: false)
          return false if organization.business&.feature_flag_enabled?(:disable_copilot_auto_review_nudge_pull_request_sidebar, default: false)
          return false if organization.plan.free?
          # Per ipm/issue-325: each user should only see the nudge once until clicked or dismissed
          # (not once per org, per repo, or per enterprise).
          return false if current_user.dismissed_notice?(nudge_id.to_s)
          return false unless repository.adminable_by?(current_user)
          return false unless org_copilot.has_copilot_for_business?
          return false unless auto_review_ready?

          true
        end

        sig { returns(T::Boolean) }
        def auto_review_ready?
          return false unless org_copilot.code_review_enabled?
          return false if org_copilot.automatic_code_review_enabled?
          # Do not show the nudge if ruleset enabled.
          return false if repository_auto_review_ruleset_enabled?

          true
        end

        sig { returns(T::Boolean) }
        def repository_auto_review_ruleset_enabled?
          default_branch = repository.default_branch
          return false unless default_branch

          evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repository, default_branch)
          evaluator&.copilot_code_review_enabled? || false
        end

        sig { override.returns(String) }
        def nudge_cta_href
          "/in-product-messaging/dismiss-and-redirect?notice=#{nudge_id}&destination_key=#{nudge_id}&group=#{nudge_category}&organization_id=#{organization.id}&repository_id=#{repository.id}&dismiss_scope=user"
        end

        sig { override.returns(String) }
        def nudge_dismiss_form_path
          dismiss_notice_path(nudge_id, nudge: true, group: nudge_category)
        end
      end
    end
  end
end
