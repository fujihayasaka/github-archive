# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    class Rules
      include GitHub::Memoizer

      class Classification < T::Enum
        enums do
          Resolvable = new(:resolvable)
          Terminal = new(:terminal)
          Ignored = new(:ignored)
          Irrelevant = new(:irrelevant)
        end
      end

      sig { params(pull_request: PullRequest, repository: Repository, mode: Mode, actor: T.untyped).void }
      def initialize(pull_request:, repository:, mode:, actor:)
        @pull_request = pull_request
        @repository = repository
        @mode = mode
        @actor = actor
      end

      sig { returns(T::Boolean) }
      def git_error_processing_rules?
        !!rule_suite&.git_error?
      end

      sig { returns(T::Boolean) }
      def disabled_on_advisory_workspaces?
        @repository.advisory_workspace? && !FeatureFlag.vexi.enabled?(:auto_merge_advisory_workspace_prs, default: false) || false
      end

      sig { returns(T.nilable(String)) }
      def invalid_merge_queue_configuration_message
        rule_suite
          &.runs_by_rule_type("merge_queue")
          &.find { _1.evaluation_metadata["duplicate_merge_queue"] && _1.failed? }
          &.message
      end

      sig { returns(T::Boolean) }
      def auto_merge_disallowed? = !@repository.auto_merge_allowed?

      sig { returns(T::Boolean) }
      def auto_merge_not_available? = !@repository.can_auto_merge_be_allowed?

      sig { returns(T::Array[Symbol]) }
      def unfulfilled_protected_branch_policy_reason_codes = rule_suite&.legacy_reason_codes || []

      sig { returns(T::Array[RulesEngine::RepositoryRuleRollup]) }
      def resolvable_rule_failures
        repository_rule_rollups_by_classification
          .fetch(Classification::Resolvable, [])
          .reject(&:passed?)
      end

      sig { returns(T::Array[RulesEngine::RepositoryRuleRollup]) }
      def terminal_rule_failures
        repository_rule_rollups_by_classification
          .values_at(Classification::Terminal, Classification::Irrelevant)
          .compact
          .reduce([], &:concat)
          .reject(&:passed?)
      end

      sig { returns(MergeConditions::PullRequestState) }
      def pull_request_states = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestState) }), MergeConditions::PullRequestState)

      sig { returns(MergeConditions::PullRequestRepoState) }
      def pull_request_repo_states = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestRepoState) }), MergeConditions::PullRequestRepoState)

      sig { returns(MergeConditions::PullRequestUserState) }
      def pull_request_user_states = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestUserState) }), MergeConditions::PullRequestUserState)

      sig { returns(MergeConditions::PullRequestMergeConflictState) }
      def pull_request_merge_conflict_states = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestMergeConflictState) }), MergeConditions::PullRequestMergeConflictState)

      sig { returns(MergeConditions::PullRequestMergeMethod) }
      def pull_request_merge_methods = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestMergeMethod) }), MergeConditions::PullRequestMergeMethod)

      sig { returns(T.nilable(MergeConditions::Stack)) }
      def stack_condition
        return nil unless stacks_enabled?
        T.cast(merge_conditions.find { _1.is_a?(MergeConditions::Stack) }, T.nilable(MergeConditions::Stack))
      end

      sig { returns(T.nilable(RuleEngine::RuleSuite)) }
      def rule_suite = pull_request_rules.rule_suite

      private

      sig { returns(T::Array[MergeConditions::BaseMergeCondition]) }
      memoize def merge_conditions = MergeConditions::Evaluator.async_evaluate(@pull_request, @actor, merge_method, skip_checks: false, enable_stacks: stacks_enabled?).sync

      sig { returns(MergeConditions::PullRequestRules) }
      def pull_request_rules = T.cast(T.must(merge_conditions.find { _1.is_a?(MergeConditions::PullRequestRules) }), MergeConditions::PullRequestRules)

      sig { returns(T::Array[RulesEngine::RepositoryRuleRollup]) }
      memoize def repository_rule_rollups = pull_request_rules.async_rule_rollups.sync

      sig { returns(T::Hash[Classification, T::Array[RulesEngine::RepositoryRuleRollup]]) }
      memoize def repository_rule_rollups_by_classification
        repository_rule_rollups.group_by do |rollup|
          # Exhaustive case statement over all rule types. Adding a new rule type will cause a Sorbet
          # type error here, forcing explicit classification.
          case type = rollup.type

          # Rules that may pass automatically over time as CI jobs complete or reviewers approve.
          when RulesEngine::RepositoryRuleRollup::RuleType::CodeScanning,
               RulesEngine::RepositoryRuleRollup::RuleType::CodeCoverage,
               RulesEngine::RepositoryRuleRollup::RuleType::CopilotCodeReview,
               RulesEngine::RepositoryRuleRollup::RuleType::PullRequest,
               RulesEngine::RepositoryRuleRollup::RuleType::RequiredDeployments,
               RulesEngine::RepositoryRuleRollup::RuleType::RequiredReviewThreadResolution,
               RulesEngine::RepositoryRuleRollup::RuleType::RequiredStatusChecks,
               RulesEngine::RepositoryRuleRollup::RuleType::RequiredWorkflowStatusChecks,
               RulesEngine::RepositoryRuleRollup::RuleType::Update,
               RulesEngine::RepositoryRuleRollup::RuleType::Workflows

            Classification::Resolvable

          # Rules that require pushing new commits or other manual intervention to resolve.
          when RulesEngine::RepositoryRuleRollup::RuleType::Authorization,
               RulesEngine::RepositoryRuleRollup::RuleType::CodeQuality,
               RulesEngine::RepositoryRuleRollup::RuleType::CommitOid,
               RulesEngine::RepositoryRuleRollup::RuleType::FileExtensionRestriction,
               RulesEngine::RepositoryRuleRollup::RuleType::FilePathRestriction,
               RulesEngine::RepositoryRuleRollup::RuleType::LicenseComplianceScanning,
               RulesEngine::RepositoryRuleRollup::RuleType::LockBranch,
               RulesEngine::RepositoryRuleRollup::RuleType::MaxFilePathLength,
               RulesEngine::RepositoryRuleRollup::RuleType::MaxFileSize,
               RulesEngine::RepositoryRuleRollup::RuleType::MaxRefUpdates,
               RulesEngine::RepositoryRuleRollup::RuleType::MergeQueueLockedRef,
               RulesEngine::RepositoryRuleRollup::RuleType::RequiredSignatures,
               RulesEngine::RepositoryRuleRollup::RuleType::SecretScanning,
               RulesEngine::RepositoryRuleRollup::RuleType::WorkflowUpdates

            Classification::Terminal

          # Rules that apply to the merge commit rather than the PR head, evaluated at merge time.
          when RulesEngine::RepositoryRuleRollup::RuleType::CommitAuthorEmailPattern,
               RulesEngine::RepositoryRuleRollup::RuleType::CommitMessagePattern,
               RulesEngine::RepositoryRuleRollup::RuleType::CommitterEmailPattern,
               RulesEngine::RepositoryRuleRollup::RuleType::MergeQueue,
               RulesEngine::RepositoryRuleRollup::RuleType::NonFastFoward,
               RulesEngine::RepositoryRuleRollup::RuleType::RequireLinearHistory

            Classification::Ignored

          # Rules that apply to repository management operations, not pull request merges.
          when RulesEngine::RepositoryRuleRollup::RuleType::BranchNamePattern,
               RulesEngine::RepositoryRuleRollup::RuleType::Creation,
               RulesEngine::RepositoryRuleRollup::RuleType::Deletion,
               RulesEngine::RepositoryRuleRollup::RuleType::RepositoryCreate,
               RulesEngine::RepositoryRuleRollup::RuleType::RepositoryTransfer,
               RulesEngine::RepositoryRuleRollup::RuleType::RestrictRepoDelete,
               RulesEngine::RepositoryRuleRollup::RuleType::RestrictRepositoryName,
               RulesEngine::RepositoryRuleRollup::RuleType::Tag,
               RulesEngine::RepositoryRuleRollup::RuleType::TagNamePattern

            Classification::Irrelevant

          else T.absurd(type)
          end
        end
      end

      # TODO update to return correct merge method for stacked PRs.
      # Currently always defaults to the fallback (:merge)
      sig { returns(T.nilable(Symbol)) }
      def merge_method
        case @mode
        when Mode::Queue, Mode::StackedQueue
          nil
        else
          @mode.strategy.serialize
        end
      end

      sig { returns(T::Boolean) }
      def stacks_enabled?
        PullRequests::Stacks.enabled?(@repository)
      end
    end
  end
end
