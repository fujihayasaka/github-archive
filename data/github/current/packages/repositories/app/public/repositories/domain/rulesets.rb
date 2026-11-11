# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Rulesets < GH::Domain::Base
      extend T::Generic
      include RuleEngine::DomainAccessorBase

      RuleSource = type_member { { fixed: RuleEngine::Types::RuleSource } }

      COMMIT_METADATA_RULE_TYPES = %w[
        commit_message_pattern
        commit_author_email_pattern
        committer_email_pattern
      ].freeze

      BRANCH_PROTECTION_RULE_TYPES = %w[
        deletion
        required_linear_history
        merge_queue
        required_review_thread_resolution
        required_deployments
        required_signatures
        pull_request
        required_status_checks
        non_fast_forward
        authorization
        tag
        merge_queue_locked_ref
        lock_branch
        code_scanning
        code_quality
        secret_scanning_results
      ].freeze

      # Ref rules (branch/tag targets)
      register_rule_implementation(RuleEngine::Rules::CreationRule.new)
      register_rule_implementation(RuleEngine::Rules::UpdateRule.new)
      register_rule_implementation(RuleEngine::Rules::DeletionRule.new)
      register_rule_implementation(RuleEngine::Rules::LinearHistoryRule.new)
      register_rule_implementation(RuleEngine::Rules::MergeQueueRule.new)
      register_rule_implementation(RuleEngine::Rules::ThreadResolutionRule.new)
      register_rule_implementation(RuleEngine::Rules::RequiredDeploymentsRule.new)
      register_rule_implementation(RuleEngine::Rules::RequiredSignaturesRule.new)
      register_rule_implementation(RuleEngine::Rules::PullRequestRule.new)
      register_rule_implementation(RuleEngine::Rules::RequiredStatusChecksRule.new)
      register_rule_implementation(RuleEngine::Rules::RequiredWorkflowStatusChecksRule.new)
      register_rule_implementation(RuleEngine::Rules::NonFastForwardRule.new)
      register_rule_implementation(RuleEngine::Rules::AuthorizationRule.new)
      register_rule_implementation(RuleEngine::Rules::TagRule.new)
      register_rule_implementation(RuleEngine::Rules::MergeQueueLockedRefRule.new)
      register_rule_implementation(RuleEngine::Rules::LockBranchRule.new)
      register_rule_implementation(RuleEngine::Rules::MaxRefUpdatesRule.new)
      register_rule_implementation(RuleEngine::Rules::CommitMessagePatternRule.new)
      register_rule_implementation(RuleEngine::Rules::CommitAuthorEmailPatternRule.new)
      register_rule_implementation(RuleEngine::Rules::CommitterEmailPatternRule.new)
      register_rule_implementation(RuleEngine::Rules::BranchNamePatternRule.new)
      register_rule_implementation(RuleEngine::Rules::TagNamePatternRule.new)
      register_rule_implementation(RuleEngine::Rules::CommitOidRule.new)
      register_rule_implementation(RuleEngine::Rules::WorkflowRule.new)
      register_rule_implementation(RuleEngine::Rules::WorkflowUpdatesRule.new)
      register_rule_implementation(RuleEngine::Rules::CodeScanningRule.new)
      register_rule_implementation(RuleEngine::Rules::CodeQualityRule.new)
      register_rule_implementation(RuleEngine::Rules::CodeCoverageRule.new)
      register_rule_implementation(RuleEngine::Rules::SecretScanningResultsRule.new)
      register_rule_implementation(RuleEngine::Rules::CopilotCodeReviewRule.new)
      register_rule_implementation(RuleEngine::Rules::LicenseComplianceScanningRule.new)

      # Push rules
      register_rule_implementation(RuleEngine::Rules::FilePathRestrictionRule.new)
      register_rule_implementation(RuleEngine::Rules::MaxFilePathLengthRule.new)
      register_rule_implementation(RuleEngine::Rules::FileExtensionRestrictionRule.new)
      register_rule_implementation(RuleEngine::Rules::MaxFileSizeRule.new)
      register_rule_implementation(RuleEngine::Rules::SecretScanningRule.new)

      # Repository policy rules
      register_rule_implementation(RuleEngine::Rules::RepositoryVisibilityRule.new)
      register_rule_implementation(RuleEngine::Rules::RepositoryCreationRule.new)
      register_rule_implementation(RuleEngine::Rules::RepositoryDeletionRule.new)
      register_rule_implementation(RuleEngine::Rules::RepositoryTransferRule.new)
      register_rule_implementation(RuleEngine::Rules::RepositoryNameRestrictionRule.new)

      # Companion rules
      register_companion_rule("required_signatures", RuleEngine::Rules::CommitSignatureRule.new)
      register_companion_rule(RuleEngine::Rules::SecretScanningRule::RULE_NAME, RuleEngine::Rules::SecretScanningContentScanRule.new)

      # Ruleset rule providers
      register_rule_provider(RuleEngine::RuleProviders::RefRulesetRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::PushRulesetRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::RepositoryPolicyRuleProvider.new)

      # Other rule providers
      register_rule_provider(RuleEngine::RuleProviders::TagRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::MergeQueueLockedRefProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::RequiredWorkflowRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::ProtectedBranchRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::KvBackedMaxRefUpdatesProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::SecretScanningRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::WorkflowUpdatesRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::CopilotSweAgentRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::ImmutableReleaseTagRuleProvider.new)

      register_default_rules("branch", %w[deletion non_fast_forward])
      register_default_rules("tag", %w[deletion non_fast_forward])

      # Priority for ruleset sources
      sig { override.returns(T::Hash[T::Class[RuleSource], Integer]) }
      def source_priority
        {
          Business => 0,
          Organization => 1,
          Repository => 2,
        }
      end

      RULESET_LIMIT = 75
      RULESET_SECOND_LIMIT = 200
      # Returns the maximum number of rulesets allowed for the given source.
      sig { override.params(source: RuleSource).returns(Integer) }
      def ruleset_limit(source)
        if source.ruleset_second_limit_enabled?
          RULESET_SECOND_LIMIT
        else
          RULESET_LIMIT
        end
      end

      # Returns the sources from which the given source can inherit rulesets.
      sig { override.params(source: T.untyped, target: String).returns(T::Array[RuleSource]) }
      def inherited_sources(source, target) # rubocop:disable Metrics/MethodLength
        if target == "push" && source.is_a?(Repository) && source.fork? && source.private? && (root_id = source.network&.root_id) && root_id != source.id
          root_repo = T.must(source.network&.root)
          GitHub::PrefillAssociations.prefill_associations(root_repo, [:organization, :owner])
          return inherited_sources(root_repo, target).concat([root_repo])
        end

        if target == "repository" && source.is_a?(User) && source.is_enterprise_managed? && source.enterprise_managed_business.present?
          return [source.enterprise_managed_business]
        end

        if source.is_a?(Repository)
          if source.owner.present? && source.emu_user_owned?
            [source.enterprise_managed_business].compact
          else
            # `async_business` and `business` do different things :(
            # `async_business` loads the business from the `owner` relationship while `business` loads it from the `organization` relationship
            # In the case of user owned forks of org repos, the `organization` is the original org, which is not what we want
            [(owner = source.owner).is_a?(Organization) ? owner : nil, source.async_business.sync].compact
          end
        elsif source.is_a?(Organization)
          [source.business].compact
        else
          []
        end
      end

      # ActiveRecord class for rulesets in the Repositories cluster.
      sig { override.returns(RuleEngine::DomainAccessorBase::RulesetClassType) }
      def ruleset_class
        RepositoryRuleset
      end
    end
  end
end
