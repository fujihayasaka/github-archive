# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class QualifiedApprovalPolicy
      include GitHub::Memoizer

      sig do
        params(
          repository: Repository,
          repo_approval_settings_resolver: T.nilable(T.proc.returns(T.nilable(PullRequests::Copilot::CodeReviewRepositoryApprovalSettings))),
        ).void
      end
      def initialize(repository:, repo_approval_settings_resolver: nil)
        @repository = repository
        @repo_approval_settings_resolver = T.let(
          repo_approval_settings_resolver,
          T.nilable(T.proc.returns(T.nilable(PullRequests::Copilot::CodeReviewRepositoryApprovalSettings))),
        )
      end

      sig { returns(T::Boolean) }
      def approval_access_allowed?
        approval_org_policy_mode != :disabled
      end

      sig { returns(T::Boolean) }
      def approval_forced_enabled_by_org?
        !organization.nil? && approval_org_policy_mode == :enabled
      end

      sig { returns(T::Boolean) }
      def approval_delegated_to_repo?
        approval_org_policy_mode == :delegated
      end

      sig { returns(T::Boolean) }
      def approval_enabled?
        return false unless approval_feature_enabled?
        return false unless approval_access_allowed?
        return true if approval_forced_enabled_by_org?
        return false unless approval_delegated_to_repo?

        repo_approval_settings&.auto_approve_when_delegated? || false
      end

      sig { returns(T::Boolean) }
      def approval_enabled_for_runtime_rollout?
        return false if approval_config_disabled?

        approval_config_enabled?
      end

      sig { returns(T::Boolean) }
      def qualified_approval_access_allowed?
        qualified_org_policy_mode != :disabled
      end

      sig { returns(T::Boolean) }
      def qualified_approval_forced_enabled_by_org?
        !organization.nil? && qualified_org_policy_mode == :enabled
      end

      sig { returns(T::Boolean) }
      def qualified_approval_delegated_to_repo?
        qualified_org_policy_mode == :delegated
      end

      sig { returns(T::Boolean) }
      def qualified_approval_enabled?
        return true if force_qualified_approval_feature_enabled?
        return false unless qualified_approval_feature_enabled?
        return false unless qualified_approval_access_allowed?
        return true if qualified_approval_forced_enabled_by_org?
        return false unless qualified_approval_delegated_to_repo?

        repo_approval_settings&.qualified_approval_when_delegated? || false
      end

      sig { returns(Symbol) }
      def effective_qualified_approval_scope
        return :all_files if force_qualified_approval_feature_enabled?
        return :disabled unless qualified_approval_access_allowed?
        return :disabled unless qualified_approval_enabled?
        return :file_patterns if repo_approval_settings&.qualified_approval_scope_when_enabled_file_patterns?

        :all_files
      end

      sig { returns(T::Array[String]) }
      def qualified_approval_file_patterns
        repo_approval_settings&.qualified_approval_file_patterns || []
      end

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def approval_counts_toward_merge_requirements_for_pull_request?(pull_request)
        async_approval_counts_toward_merge_requirements_for_pull_request?(pull_request).sync
      end

      sig { params(pull_request: PullRequest).returns(Promise[T::Boolean]) }
      def async_approval_counts_toward_merge_requirements_for_pull_request?(pull_request)
        scope = effective_qualified_approval_scope
        case scope
        when :all_files
          Promise.resolve(T.let(true, T::Boolean))
        when :file_patterns
          async_all_changed_paths_match_file_patterns?(pull_request)
        when :disabled
          Promise.resolve(T.let(false, T::Boolean))
        else
          raise ArgumentError, "Unsupported qualified approval scope: #{scope.inspect}"
        end
      end

      sig { params(review: PullRequestReview, pull_request: PullRequest).returns(T::Boolean) }
      def globally_qualifies_review?(review:, pull_request:)
        async_globally_qualifies_review?(review: review, pull_request: pull_request).sync
      end

      sig { params(review: PullRequestReview, pull_request: PullRequest).returns(Promise[T::Boolean]) }
      def async_globally_qualifies_review?(review:, pull_request:)
        return Promise.resolve(T.let(false, T::Boolean)) unless review.approved?

        async_approval_counts_toward_merge_requirements_for_pull_request?(pull_request)
      end

      private

      sig { returns(Repository) }
      attr_reader :repository

      sig do
        returns(T.nilable(T.all(
          User,
          Configurable::CopilotCodeReviewApprovalAccess,
          Configurable::CopilotCodeReviewQualifiedApprovalAccess,
        )))
      end
      memoize def organization
        repository.organization
      end

      sig { returns(T.nilable(PullRequests::Copilot::CodeReviewRepositoryApprovalSettings)) }
      memoize def repo_approval_settings
        return @repo_approval_settings_resolver.call if @repo_approval_settings_resolver

        PullRequests::Copilot::CodeReviewRepositoryApprovalSettings.find_by(repository: repository)
      end

      sig { returns(T::Boolean) }
      def approval_config_disabled?
        raw_approval_org_policy_mode == :disabled
      end

      sig { returns(T::Boolean) }
      def approval_config_enabled?
        return true if raw_approval_org_policy_mode == :enabled

        repo_approval_settings&.auto_approve_when_delegated? || false
      end

      sig { returns(Symbol) }
      memoize def raw_approval_org_policy_mode
        org = organization
        return :unset unless org

        access = org.raw_copilot_code_review_approval_access
        return :unset unless access

        case access
        when Configurable::CopilotCodeReviewApprovalAccess::State::ALL_REPOS
          :enabled
        when Configurable::CopilotCodeReviewApprovalAccess::State::NO_POLICY
          :delegated
        when Configurable::CopilotCodeReviewApprovalAccess::State::SELECTED_REPOS
          if PullRequests::Copilot::RepoEnablement.enabled_for_repository?(repository, setting_type: :approval)
            :enabled
          else
            :disabled
          end
        when Configurable::CopilotCodeReviewApprovalAccess::State::DISABLED
          :disabled
        else
          T.absurd(access)
        end
      end

      sig { returns(Symbol) }
      memoize def approval_org_policy_mode
        return :delegated unless organization
        return :delegated unless approval_org_policy_rollout_enabled?

        T.must(organization).copilot_code_review_approval_policy_for(repository)
      end

      sig { returns(Symbol) }
      memoize def qualified_org_policy_mode
        return :delegated unless organization
        return :delegated unless qualified_approval_org_policy_rollout_enabled?

        T.must(organization).copilot_code_review_qualified_approval_policy_for(repository)
      end

      sig { returns(T::Boolean) }
      memoize def approval_feature_enabled?
        repository.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
      end

      sig { returns(T::Boolean) }
      memoize def qualified_approval_feature_enabled?
        repository.feature_enabled_for_repo_or_owner?(:ccr_copilot_qualified_approvals)
      end

      sig { returns(T::Boolean) }
      memoize def force_qualified_approval_feature_enabled?
        FeatureFlag.vexi.enabled?(
          :ccr_force_copilot_qualified_approvals,
          repository,
          repository.owner,
          default: false,
        )
      end

      sig { returns(T::Boolean) }
      memoize def approval_org_policy_rollout_enabled?
        T.must(organization).feature_flag_enabled?(:ccr_auto_approve_reviews, default: false)
      end

      sig { returns(T::Boolean) }
      memoize def qualified_approval_org_policy_rollout_enabled?
        T.must(organization).feature_flag_enabled?(:ccr_copilot_qualified_approvals, default: false)
      end

      sig { params(pull_request: PullRequest).returns(Promise[T::Boolean]) }
      def async_all_changed_paths_match_file_patterns?(pull_request)
        async_trusted_changed_paths(pull_request).then do |changed_paths|
          next false if changed_paths.nil? || changed_paths.empty?

          matching_paths = matching_paths_for(
            changed_paths: changed_paths,
            file_patterns: qualified_approval_file_patterns,
          )

          !matching_paths.empty? && matching_paths == changed_paths.to_set
        end
      end

      sig { params(pull_request: PullRequest).returns(Promise[T.nilable(T::Array[String])]) }
      def async_trusted_changed_paths(pull_request)
        pull_request.async_build_trusted_comparison.then do |trusted_comparison|
          trusted_comparison.async_build_diff.then do |diff|
            diff.deltas.flat_map(&:paths).uniq
          end
        end.catch do |error|
          Failbot.report(error, "gh.pull_request.id": pull_request.id)
          Promise.resolve(T.let(nil, T.nilable(T::Array[String])))
        end
      end

      sig do
        params(
          changed_paths: T::Array[String],
          file_patterns: T::Array[String],
        ).returns(T::Set[String])
      end
      def matching_paths_for(changed_paths:, file_patterns:)
        return Set.new if changed_paths.empty? || file_patterns.empty?

        tree = Codeowners::Tree.new
        changed_paths.each { |path| tree.insert(path) }

        matching_files = T.let(Set.new, T::Set[String])

        file_patterns.each do |file_pattern|
          next if file_pattern.blank?

          matches = tree.match(file_pattern)
          next if matches.blank?

          matching_files.merge(matches)
        end

        matching_files
      end
    end
  end
end
