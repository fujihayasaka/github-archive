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

      sig { params(actor: T.nilable(T.any(User, Organization, Business)), current_repository: T.nilable(Repository), pull_request: T.nilable(PullRequest)).void }
      def initialize(actor:, current_repository:, pull_request: nil)
        @actor = actor
        @repo = current_repository
        @pull_request = pull_request
        @supported_languages = T.let(SUPPORTED_LANGUAGES.dup, T::Array[String])
      end

      # Public: Returns true if we should trigger automatic reviews for new PRs on this repository.
      sig { returns(T::Boolean) }
      def auto_reviewable?
        return false if actor_feature_enabled?(:copilot_reviews_automatic_pull_request_review_disabled)
        return false unless repo_or_owner_flag_enabled?(:copilot_reviews_automatic_pull_request_review)
        return false unless can_create_review_request?

        true
      end

      # Public: Returns true if we should trigger automatic reviews based on repo rules.
      sig { returns(T::Boolean) }
      def repo_rule_auto_reviewable?
        return false if actor_feature_enabled?(:copilot_reviews_automatic_pull_request_review_disabled)
        return false unless can_create_review_request?
        return false unless @pull_request&.base_branch_rule_evaluator&.automatic_copilot_code_review_enabled?

        true
      end

      # Public: Validates if Copilot should be suggested as a reviewer.
      sig { returns(T::Boolean) }
      def should_suggest_reviewer?
        return false unless can_create_review_request?
        return false if repo_or_owner_flag_enabled?(:copilot_reviews_automatic_pull_request_review)
        return false if repo_or_owner_flag_enabled?(:copilot_reviews_automatic_repo_rule)
        return true if @pull_request.nil?
        return false if @pull_request.base_branch_rule_evaluator&.automatic_copilot_code_review_enabled?

        contains_reviewable_files?(@pull_request)
      end

      # Public: Validates if the actor can create a Copilot review request.
      # Can also be used to answer other feature-visibility questions, like repo rule settings.
      sig { returns(T::Boolean) }
      def can_create_review_request?
        log("checking if actor can create review request")

        return false unless actor_eligible?
        return false unless repository_eligible?
        return false unless app_installed?
        return false unless has_quota_remaining?

        log("actor can create review request")
        true
      end


      sig { returns(CodeReviewAccess::Reason) }
      def can_create_review_request_reason
        log("checking if actor can create review request")

        return Reason.actor_ineligible unless actor_eligible?
        return Reason.repository_ineligible unless repository_eligible?
        return Reason.app_not_installed unless app_installed?
        return Reason.actor_has_no_quota_remaining unless has_quota_remaining?

        log("actor can create review request")
        Reason.eligible
      end

      # Public: Validates if the actor has quota remaining to create a Copilot review request.
      sig { returns(T::Boolean) }
      def has_quota_remaining?
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

      private

      sig { returns(PullRequests::Copilot::CodeReviewQuota) }
      memoize def code_review_quota
        PullRequests::Copilot::CodeReviewQuota.new(copilot_user: copilot_user)
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
        return true if actor_feature_enabled?(:copilot_code_review_bypass_access_checks)
        log("actor is not in copilot_code_review_bypass_access_checks")

        return true if actor_feature_enabled?(:copilot_code_review_v1)
        log("actor is not in copilot_code_review_v1")

        return false unless actor_feature_enabled?(:copilot_code_review_public_preview)
        log("actor is in copilot_code_review_public_preview")

        # User is in the public preview, so we also require:
        # - Any Copilot license
        # - Beta features opted in
        if @actor.is_a?(Business)
          return false unless copilot_business&.beta_features_github_chat_enabled?
          log("business actor has beta features enabled")
        elsif @actor.is_a?(Organization)
          return false unless copilot_organization&.beta_features_github_chat_enabled?
          log("org actor has beta features enabled")
        elsif @actor.is_a?(User)
          return false unless copilot_user&.has_copilot_access?
          log("user actor has copilot access")
          return false unless copilot_user&.beta_features_github_chat_enabled?
          log("user actor has beta features enabled")
        end
        log("actor is eligible")
        true
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
        "JavaScript+ERB"
      ].freeze, T::Array[String])

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def contains_reviewable_files?(pull_request)
        if actor_feature_enabled?(:copilot_code_review_check_filenames_for_reviewability)
          contains_reviewable_filenames?(pull_request) || contains_reviewable_file_types?(pull_request)
        else
          contains_reviewable_file_types?(pull_request)
        end
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

      # Private: Checks if the reviewer app is installed.
      sig { returns(T::Boolean) }
      def app_installed?
        return false unless Apps::Privileged::CopilotPullRequestReviewer.installed?
        log("app is installed")
        true
      end

      # Private: Checks if the repository is accessible.
      sig { returns(T::Boolean) }
      def repository_eligible?
        return true if Rails.env.development?
        log("not in development mode")

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
        @actor.feature_enabled?(feature)
      end

      # Private: Checks if a flag is enabled for the repo or its owner.
      sig { params(flag: Symbol).returns(T::Boolean) }
      def repo_or_owner_flag_enabled?(flag)
        @repo&.feature_enabled_for_repo_or_owner?(flag)
      end

      sig { returns(T.nilable(::Copilot::Public::User)) }
      memoize def copilot_user
        return nil unless @actor.is_a?(User)
        ::Copilot::Public::User.new(@actor)
      end

      sig { returns(T.nilable(::Copilot::Organization)) }
      memoize def copilot_organization
        return nil unless @actor.is_a?(Organization)
        ::Copilot::Organization.new(@actor)
      end

      sig { returns(T.nilable(::Copilot::Business)) }
      memoize def copilot_business
        return nil unless @actor.is_a?(Business)
        ::Copilot::Business.new(@actor)
      end

      sig { returns(T::Array[String]) }
      def all_supported_and_experimental_languages
        @supported_languages << "C++" if repo_or_owner_flag_enabled?(:expand_supported_languages_cpp)
        @supported_languages << "C" if repo_or_owner_flag_enabled?(:copilot_code_review_enable_c_support)
        @supported_languages
      end
    end
  end
end
