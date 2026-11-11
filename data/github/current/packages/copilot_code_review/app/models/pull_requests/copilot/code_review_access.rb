# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    class CodeReviewAccess
      include GitHub::Memoizer
      include GitHub::ResilienceMixin

      class Reason < T::Struct
        const :access, T::Boolean, default: false
        const :reason, Symbol

        sig { returns(T.attached_class) }
        def self.eligible = new(access: true, reason: :eligible)

        sig { returns(T.attached_class) }
        def self.actor_ineligible = new(access: false, reason: :actor_ineligible)

        sig { returns(T.attached_class) }
        def self.repository_ineligible = new(access: false, reason: :repository_ineligible)

        sig { returns(T.attached_class) }
        def self.app_not_installed = new(access: false, reason: :app_not_installed)

        sig { returns(T.attached_class) }
        def self.actor_has_no_quota_remaining = new(access: false, reason: :actor_has_no_quota_remaining)

        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          return false unless other.is_a?(self.class)
          access == other.access && reason == other.reason
        end
      end

      sig { params(actor: T.nilable(User), current_repository: T.nilable(Repository), pull_request: T.nilable(PullRequest), bypass_quota_check: T.nilable(T::Boolean)).void }
      def initialize(actor:, current_repository:, pull_request: nil, bypass_quota_check: false)
        @actor = actor
        @repo = current_repository
        @pull_request = pull_request
        @bypass_quota_check = bypass_quota_check
      end

      # Public: Returns true if automatic reviews are enabled, use auto_reviewable? to determine if one should actually be triggered.
      sig { returns(T::Boolean) }
      def automatic_reviews_enabled?
        return false if actor_feature_enabled?(:copilot_reviews_automatic_pull_request_review_disabled)
        return true if repo_or_owner_flag_enabled?(:copilot_reviews_automatic_pull_request_review)

        return true if copilot_user&.automatic_code_review_enabled? && actor_individual_plan?
        return true if @pull_request&.base_branch_rule_evaluator&.copilot_code_review_enabled?

        false
      end

      # Public: Returns true if we should trigger automatic reviews for new PRs on this repository.
      sig { returns(T::Boolean) }
      def auto_reviewable?
        return false unless can_create_review_request?
        automatic_reviews_enabled?
      end

      # Public: Validates if Copilot should be suggested as a reviewer.
      sig { returns(T::Boolean) }
      def should_suggest_reviewer?
        can_create_review_request?
      end

      # Public: Validates if Copilot can be suggested as a reviewer when searching inside a repository.
      sig { returns(T::Boolean) }
      def should_suggest_reviewer_for_repository?
        repository_eligible?
      end

      # Public: Validates if the actor can create a Copilot review request.
      # Can also be used to answer other feature-visibility questions, like repo rule settings.
      sig { returns(T::Boolean) }
      def can_create_review_request?
        can_create_review_request_reason.access
      end

      sig { returns(CodeReviewAccess::Reason) }
      def can_create_review_request_reason
        reason = if !(actor_eligible? || should_bill_to_organization?)
          Reason.actor_ineligible
        elsif !repository_eligible?
          Reason.repository_ineligible
        elsif !app_available?
          Reason.app_not_installed
        elsif !has_quota_remaining?
          Reason.actor_has_no_quota_remaining
        else
          Reason.eligible
        end

        log("review_request_access_check", context: { outcome: reason.access ? "eligible" : "denied", denial_reason: reason.reason.to_s })
        reason
      end

      # Public: Helper used to check for Reason.actor_has_no_quota_remaining specifically.
      sig { returns(T::Boolean) }
      def reason_actor_has_no_quota_remaining?
        can_create_review_request_reason == Reason.actor_has_no_quota_remaining
      end

      # Public: Validates if the actor has quota remaining to create a Copilot review request.
      sig { returns(T::Boolean) }
      def has_quota_remaining?
        if FeatureFlag.vexi.enabled?("ccr_use_new_policy_on_cca", @repo, default: false) && is_copilot_bot?
          return true
        end
        return true if bypass_quota_check?
        return true if should_bill_to_organization?

        code_review_quota.has_quota_remaining?
      end

      # Public: Returns the remaining quota for the actor to create a Copilot review request.
      sig { returns(Float) }
      def remaining_quota
        code_review_quota.remaining_quota
      end

      # Public: Returns when the quota for the actor will be reset.
      sig { returns(Date) }
      def quota_reset_date
        code_review_quota.quota_reset_date
      end

      # Public: Returns whether the actor can access Copilot code review in the IDE
      sig { returns(T::Boolean) }
      def can_access_code_review_in_ide?
        # always false if any of the user's businesses have CCR disabled, since we have
        # no way to know which code the user is working on in the IDE
        return false if copilot_user&.copilot_businesses&.any? { |business| !business.business_object.code_review_repository_access_enabled? }
        actor_eligible?
      end

      sig { returns(T::Boolean) }
      memoize def should_bill_to_organization?
        unless copilot_organization
          debug_log_org_billing("no_copilot_organization")
          return false
        end

        unless org_or_business_flag_enabled?(:copilot_code_review_direct_org_billing)
          debug_log_org_billing("direct_org_billing_flag_disabled")
          return false
        end

        if actor_eligible?
          debug_log_org_billing("actor_already_eligible")
          return false
        end

        unless direct_org_billing_policy_enabled?
          debug_log_org_billing("direct_org_billing_policy_disabled")
          return false
        end

        result = copilot_organization&.eligible_for_direct_org_billing? || false
        debug_log_org_billing("direct_org_billing_limiter", outcome: result ? "eligible" : "denied")
        result
      end

      # Returns true if CCR should mint an org (`ghs_`) installation token for this review
      # instead of a user (`ghu_`) token, so CAPI sees a TypeOrg actor and bills the org
      # directly. Gated on the per-review billing decision (`should_bill_to_organization?`)
      # plus a separate cutover feature flag so the token type can be rolled out
      # independently of the existing direct-org-billing rollout.
      sig { returns(T::Boolean) }
      def should_mint_org_token?
        return false unless should_bill_to_organization?
        org_or_business_flag_enabled?(:copilot_code_review_org_token_billing)
      end

      private

      sig { returns(PullRequests::Copilot::CodeReviewQuota) }
      memoize def code_review_quota
        PullRequests::Copilot::CodeReviewQuota.new(copilot_user: copilot_user)
      end

      sig { returns(T::Boolean) }
      def bypass_quota_check?
        !!@bypass_quota_check
      end

      sig { params(message: String, context: T::Hash[Symbol, T.untyped]).void }
      def log(message, context: {})
        GitHub.logger.info("copilot_code_review_access: #{message}",
          "gh.repository.id" => @repo&.id,
          "gh.repository.nwo" => @repo&.name_with_display_owner,
          "gh.user.id" => @actor&.id,
          "gh.user.login" => @actor&.display_login,
          "gh.pull_request.id" => @pull_request&.id,
          "gh.pull_request.url" => @pull_request&.url,
          **context.transform_keys { |k| "gh.code_review.#{k}" },
        )
      end

      # Private: Logs org billing debug info only when the debug feature flag is enabled.
      # Enable :copilot_code_review_debug_org_billing on a repo or its owner to activate.
      sig { params(reason: String, outcome: String).void }
      def debug_log_org_billing(reason, outcome: "denied")
        return unless repo_or_owner_flag_enabled?(:copilot_code_review_debug_org_billing)

        log("should_bill_to_organization", context: { outcome: outcome, reason: reason })
      end

      sig { returns(T::Boolean) }
      memoize def actor_eligible?
        is_copilot = FeatureFlag.vexi.enabled?("ccr_use_new_policy_on_cca", @repo, default: false) && is_copilot_bot?
        eligible = is_copilot || (copilot_user&.has_copilot_access? && !copilot_user&.has_limited_access? && !!copilot_user&.code_review_enabled?)

        unless eligible
          denial = if !copilot_user&.has_copilot_access?
            "no_copilot_access"
          elsif copilot_user&.has_limited_access?
            "free_tier_only"
          else
            "code_review_policy_disabled"
          end
          log("actor_eligibility_check", context: { outcome: "ineligible", denial_reason: denial })
        end

        !!eligible
      end

      sig { returns(T::Boolean) }
      def actor_individual_plan?
        !!(copilot_user&.has_trial_access? || copilot_user&.has_free_access? || copilot_user&.has_pro_access? || copilot_user&.has_pro_plus_access? || copilot_user&.has_max_access?)
      end

      # Private: Checks if the reviewer app is available.
      sig { returns(T::Boolean) }
      def app_available?
        Apps::Privileged.integration(:copilot_pull_request_reviewer).present?
      end

      # Private: Checks if the repository is accessible.
      sig { returns(T::Boolean) }
      def repository_eligible?
        return true if Rails.env.development?

        unless enterprise_allows_code_review_in_repositories?
          log("repository_eligibility_check", context: { outcome: "ineligible", denial_reason: "enterprise_disallows_code_review" })
          return false
        end

        if repo_or_owner_flag_enabled?(:copilot_code_review_disable_via_chat_setting) && copilot_organization&.dotcom_chat_disabled?
          log("repository_eligibility_check", context: { outcome: "ineligible", denial_reason: "chat_disabled_by_org" })
          return false
        end

        # TEMP: disabling this for now because it caused some unexpected issues that need product input
        # return false if copilot_organization&.code_review_disabled?

        true
      end

      # Private: Checks if a feature is enabled for the actor.
      sig { params(feature: Symbol).returns(T::Boolean) }
      def actor_feature_enabled?(feature)
        return false if @actor.nil?
        @actor.feature_flag_enabled?(feature, default: false)
      end

      # Private: Checks if a flag is enabled for the repo or its owner.
      sig { params(flag: Symbol).returns(T::Boolean) }
      def repo_or_owner_flag_enabled?(flag)
        @repo&.feature_enabled_for_repo_or_owner?(flag)
      end

      sig { params(flag: Symbol).returns(T::Boolean) }
      def org_or_business_flag_enabled?(flag)
        organization = @repo&.organization
        return false unless organization
        organization.feature_flag_enabled?(flag, default: false) || !!organization.business&.feature_flag_enabled?(flag, default: false)
      end

      sig { returns(T::Boolean) }
      def enterprise_allows_code_review_in_repositories?
        return true unless @repo

        business = @repo.business
        return true unless business

        business.code_review_repository_access_enabled?
      end

      sig { returns(T.nilable(::Copilot::Public::User)) }
      memoize def copilot_user
        return nil unless @actor.is_a?(User)
        ::Copilot::Public::User.for(@actor)
      end

      sig { returns(T.nilable(::Copilot::Organization)) }
      memoize def copilot_organization
        org = @repo&.organization || @pull_request&.repository&.organization
        ::Copilot::Organization.new(org) if org.present?
      end

      sig { returns(T.nilable(::Copilot::Business)) }
      memoize def copilot_business
        business = copilot_organization&.business
        ::Copilot::Business.new(business) if business.present?
      end

      # Private: Checks if the actor is the Copilot bot (either the pull request reviewer bot or the SWE agent bot).
      # When running CCR on the Agent Platform, an access check will be performed with the Bots. This helper method
      # can be used to check if the actor is any of the allowed Copilot bots.
      sig { returns(T::Boolean) }
      def is_copilot_bot?
        return false unless @actor.is_a?(::Bot)

        bot = @actor
        ccr_id = Apps::Privileged::Registry.app_id(app_alias: :copilot_pull_request_reviewer, type: "Integration")
        swe_agent_id = Apps::Privileged::Registry.app_id(app_alias: :copilot_swe_agent, type: "Integration")

        T.must(bot.integration).id == swe_agent_id || T.must(bot.integration).id == ccr_id
      end

      sig { returns(T::Boolean) }
      def direct_org_billing_policy_enabled?
        return false unless copilot_organization
        with_database_error_fallback(fallback: false) do
          return false unless T.must(copilot_organization).has_configuration?
          ::Copilot::Policies::CcrDirectOrgBilling.enabled?(T.must(copilot_organization))
        end
      end
    end
  end
end
