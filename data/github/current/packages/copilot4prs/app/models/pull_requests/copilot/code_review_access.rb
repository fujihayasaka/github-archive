# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    class CodeReviewAccess
      include GitHub::Memoizer

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
        @supported_languages = T.let(SUPPORTED_LANGUAGES.dup, T::Array[String])
      end

      # Public: Returns true if automatic reviews are enabled, use auto_reviewable? to determine if one should actually be triggered.
      sig { returns(T::Boolean) }
      def automatic_reviews_enabled?
        return false if actor_feature_enabled?(:copilot_reviews_automatic_pull_request_review_disabled)
        return true if repo_or_owner_flag_enabled?(:copilot_reviews_automatic_pull_request_review)

        return true if copilot_user&.automatic_code_review_enabled? && actor_individual_plan?
        return true if @pull_request&.base_branch_rule_evaluator&.automatic_copilot_code_review_enabled?
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
        log("checking if Copilot should be suggested as a reviewer")

        return false unless can_create_review_request?
        return false if automatic_reviews_enabled?
        return contains_reviewable_files?(@pull_request) if @pull_request.present?

        true
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
        log("checking if actor can create review request")

        return Reason.actor_ineligible unless actor_eligible?
        return Reason.repository_ineligible unless repository_eligible?
        return Reason.app_not_installed unless app_available?
        return Reason.actor_has_no_quota_remaining unless has_quota_remaining?

        log("actor can create review request")
        Reason.eligible
      end

      # Public: Helper used to check for Reason.actor_has_no_quota_remaining specifically.
      sig { returns(T::Boolean) }
      def reason_actor_has_no_quota_remaining?
        can_create_review_request_reason == Reason.actor_has_no_quota_remaining
      end

      # Public: Validates if the actor has quota remaining to create a Copilot review request.
      sig { returns(T::Boolean) }
      def has_quota_remaining?
        if bypass_quota_check?
          log("bypassing has_quota_remaining?")
          return true
        end

        log("checking if actor has quota remaining to create review request")
        return false unless code_review_quota.has_quota_remaining?
        log("actor has quota remaining to create review request")
        true
      end

      # Public: Returns the remaining quota for the actor to create a Copilot review request.
      sig { returns(Float) }
      def remaining_quota
        log("checking quota remaining for actor to create review request")
        code_review_quota.remaining_quota
      end

      # Public: Returns when the quota for the actor will be reset.
      sig { returns(Date) }
      def quota_reset_date
        log("checking quota reset datetime for actor to create review request")
        code_review_quota.quota_reset_date
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

      sig { params(message: String).void }
      def log(message)
        GitHub.logger.info("copilot_code_review_access: #{message}",
          "gh.repository.id" => @repo&.name,
          "gh.user.id" => @actor&.id,
          "gh.user.login" => @actor&.display_login,
          "gh.pull_request.id" => @pull_request&.id,
        )
      end

      sig { returns(T::Boolean) }
      def actor_eligible?
        log("checking if actor is eligible")
        return false unless copilot_user&.has_copilot_access?

        log("actor has #{copilot_user&.has_limited_access? ? 'free' : 'paid'} copilot access")
        return false if copilot_user&.has_limited_access? && !actor_feature_enabled?(:ccr_access_free)

        if actor_feature_enabled?(:copilot_code_review_policy)
          return false unless copilot_user&.code_review_enabled?
          log("actor has Copilot code review policy enabled")
        else
          return false unless copilot_user&.dotcom_chat_enabled?
          log("actor has Copilot policy enabled")
        end

        true
      end

      sig { returns(T::Boolean) }
      def actor_individual_plan?
        !!((actor_feature_enabled?(:ccr_access_free) && copilot_user&.has_limited_access?) || copilot_user&.has_trial_access? || copilot_user&.has_free_access? || copilot_user&.has_pro_access? || copilot_user&.has_pro_plus_access? || copilot_user&.has_max_access?)
      end

      # see also https://github.com/github/copilot-api/blob/03cceaa6f937570716bc047aea435aef242a88dd/pkg/codereviewagent/planner.go
      SUPPORTED_LANGUAGES = T.let([
        "Go",
        "Java",
        "Markdown",
        "Rust",
        "TypeScript",
        "Ruby",
        "HTML+ERB",
        "Python",
        "TOML",
        "YAML",
        "Protocol Buffer",
        "TSX",
        "JavaScript",
        "Vue",
        "Kusto",
        "RenderScript",
        "GCC Machine Description",
        "C#",
        "HTML+Razor",
        "Java Server Pages",
        "Jupyter Notebook",
        "JavaScript+ERB",
        "C++",
        "C",
        "Kotlin",
        "Swift",
      ].freeze, T::Array[String])

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def contains_reviewable_files?(pull_request)
        return true if copilot_user&.beta_features_github_chat_enabled? || actor_feature_enabled?(:copilot_code_review_enable_all_languages)

        contains_reviewable_filenames?(pull_request) || contains_reviewable_file_types?(pull_request)
      end

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def contains_reviewable_filenames?(pull_request)
        pull_request.diffs.filenames.any? do |filename|
          Linguist::Language.find_by_filename(filename)&.map(&:name).intersect?(all_supported_and_experimental_languages)
        end
      end

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def contains_reviewable_file_types?(pull_request)
        pull_request.diffs.file_types.any? do |file_type|
          Linguist::Language.find_by_extension(file_type)&.map(&:name).intersect?(all_supported_and_experimental_languages)
        end
      end

      # Private: Checks if the reviewer app is available.
      sig { returns(T::Boolean) }
      def app_available?
        return false unless Apps::Privileged.integration(:copilot_pull_request_reviewer).present?
        log("app is installed")
        true
      end

      # Private: Checks if the repository is accessible.
      sig { returns(T::Boolean) }
      def repository_eligible?
        return true if Rails.env.development?
        log("not in development mode")

        if repo_or_owner_flag_enabled?(:copilot_code_review_policy)
          return false unless enterprise_allows_code_review_in_repositories?
          log("enterprise allows code review in repositories")

          return false if repo_or_owner_flag_enabled?(:copilot_code_review_disable_via_chat_setting) && copilot_organization&.dotcom_chat_disabled?
          log("organization and/or parent enterprise has copilot enabled") if copilot_organization

          return false if actor_feature_enabled?(:ccr_access_free) && copilot_user&.has_limited_access? && copilot_organization&.code_review_disabled?
          log("organization has copilot code review enabled and user is not limited_access") if copilot_user && copilot_organization
        else
          return false if repo_or_owner_flag_enabled?(:copilot_code_review_disable_via_chat_setting) && copilot_organization&.dotcom_chat_disabled?
          log("organization and/or parent enterprise has copilot enabled") if copilot_organization

          return false if actor_feature_enabled?(:ccr_access_free) && copilot_user&.has_limited_access? && copilot_organization&.dotcom_chat_disabled?
          log("organization and/or parent enterprise has copilot enabled and user is not limited_access") if copilot_user && copilot_organization
        end

        return true if !@repo&.public?
        log("repo is public")

        return false unless actor_feature_enabled?(:copilot_code_review_public_repo_reviews)
        log("actor is in copilot_code_review_public_repo_reviews")

        log("repository is eligible")
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
        ::Copilot::Public::User.new(@actor)
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

      sig { returns(T::Array[String]) }
      def all_supported_and_experimental_languages
        if copilot_user&.beta_features_github_chat_enabled?
          @supported_languages += %w[HTML Text]
        end

        @supported_languages
      end
    end
  end
end
