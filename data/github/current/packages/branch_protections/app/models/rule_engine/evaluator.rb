# typed: true
# frozen_string_literal: true

module RuleEngine
  class Evaluator
    extend T::Sig
    extend RuleEngine::Timing

    # The order of the rules in this constant dictates the order they will appear in the REST API docs
    REGISTERED_RULES = T.let({
      "creation" => Rules::CreationRule.new,
      "update" => Rules::UpdateRule.new,
      "deletion" => Rules::DeletionRule.new,
      "required_linear_history" => Rules::LinearHistoryRule.new,
      "merge_queue" => Rules::MergeQueueRule.new,
      "required_review_thread_resolution" => Rules::ThreadResolutionRule.new,
      "required_deployments" => Rules::RequiredDeploymentsRule.new,
      "required_signatures" => Rules::RequiredSignaturesRule.new,
      "pull_request" => Rules::PullRequestRule.new,
      "required_status_checks" => Rules::RequiredStatusChecksRule.new,
      "required_workflow_status_checks" => Rules::RequiredWorkflowStatusChecksRule.new,
      "non_fast_forward" => Rules::NonFastForwardRule.new,
      "authorization" => Rules::AuthorizationRule.new,
      "tag" => Rules::TagRule.new,
      "merge_queue_locked_ref" => Rules::MergeQueueLockedRefRule.new,
      "lock_branch" => Rules::LockBranchRule.new,
      "max_ref_updates" => Rules::MaxRefUpdatesRule.new,
      "commit_message_pattern" => Rules::CommitMessagePatternRule.new,
      "commit_author_email_pattern" => Rules::CommitAuthorEmailPatternRule.new,
      "committer_email_pattern" => Rules::CommitterEmailPatternRule.new,
      "branch_name_pattern" => Rules::BranchNamePatternRule.new,
      "tag_name_pattern" => Rules::TagNamePatternRule.new,
      "file_path_restriction" => Rules::FilePathRestrictionRule.new,
      "max_file_path_length" => Rules::MaxFilePathLengthRule.new,
      "file_extension_restriction" => Rules::FileExtensionRestrictionRule.new,
      "max_file_size" => RuleEngine::Rules::MaxFileSizeRule.new,
      "commit_oid" => Rules::CommitOidRule.new,
      "workflows" => Rules::WorkflowRule.new,
      Rules::SecretScanningRule::RULE_NAME => Rules::SecretScanningRule.new,
      "workflow_updates" => Rules::WorkflowUpdatesRule.new,
      "code_scanning" => Rules::CodeScanningRule.new,
      "restrict_repo_delete" => RuleEngine::Rules::RepositoryDeletionRule.new,
      "repository_transfer" => Rules::RepositoryTransferRule.new,
      "restrict_repository_name" => RuleEngine::Rules::RepositoryNameRestrictionRule.new,
      "restrict_repo_visibility" => RuleEngine::Rules::RepositoryVisibilityRule.new,
    }.freeze, T::Hash[String, BaseRule])

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
    ].freeze

    DEFAULT_RULES = %w[
      deletion
      non_fast_forward
    ].freeze

    COMPANION_RULES = T.let([
      Rules::CommitSignatureRule.new,
      Rules::SecretScanningContentScanRule.new
    ].map { |rule| [rule.rule_name, rule] }.to_h, T::Hash[String, BaseRule]).freeze

    ##
    # This is a mapping of rule types to their companion rule implementations. These rules are evaluated alongside the main rule, and results
    # will be merged.
    #
    COMPANION_RULE_MAPPINGS = {
      "required_signatures" => Rules::CommitSignatureRule.new,
      Rules::SecretScanningRule::RULE_NAME => Rules::SecretScanningContentScanRule.new
    }.freeze

    RULE_PROVIDERS = T.let([
      RuleProviders::TagRuleProvider.new,
      RuleProviders::MergeQueueLockedRefProvider.new,
      RuleProviders::RequiredWorkflowRuleProvider.new,
      RuleProviders::ProtectedBranchRuleProvider.new,
      RuleProviders::KvBackedMaxRefUpdatesProvider.new,
      RuleProviders::SecretScanningRuleProvider.new,
      RuleProviders::WorkflowUpdatesRuleProvider.new,
      RuleProviders::RefRulesetRuleProvider.new,
      RuleProviders::PushRulesetRuleProvider.new,
      RuleProviders::MemberPrivilegeRulesetRuleProvider.new,
    ].freeze, T::Array[RuleProvider])

    METADATA_TYPES = [:blob, :commit, :ref]

    # Evaluate rules for a single ref_update
    #
    # repository              - The repository to evaluate rules on
    # ref_update              - The ref_update being proposed
    # actor                   - The actor proposing the ref_update
    # metadata_source         - (Optional) source for Spokes-related data (used for testing)
    # dry_run                 - Whether the result of this run will be commited
    # phase                   - Phase of the evaluation used to determine which rules are evaluated. Defaults to PostReceive, which only evaluates ref rules.
    # options                 - {
    #  :server_merge - Boolean indicating whether this run uses a server-generated merge commit as the after_oid
    #  :fetch_and_merge - Boolean indicating whether this run is for a fork sync operation
    #  :pre_receive_rule_suites - Array of RuleSuites that were generated during the pre-receive phase (required when evaluating the post-receive phase)
    #  :commit_refs_evaluation - Boolean indicating whether this run is evaluated during GitAuth's commit_refs
    # }
    #
    # Returns RuleSuite containing the results of the evaluation
    sig do
      params(
        repository: Repository,
        ref_update: Git::Ref::Update,
        actor: RuleEngine::Types::Actor,
        phase: T.nilable(Types::Phase),
        metadata_source: T.nilable(RuleEngine::MetadataSources::Base),
        dry_run: T::Boolean,
        options: T::Hash[Symbol, T.untyped]
      ).returns(RuleSuite).checked(:always).on_failure(:raise)
    end
    def self.evaluate_rules_one(repository,
                                ref_update,
                                actor,
                                phase: RuleEngine::Types::Phase::PostReceive,
                                metadata_source: nil,
                                dry_run: false,
                                options: {})
      T.must(evaluate_rules(repository, [ref_update], actor, phase:, metadata_source:, dry_run:, options:).first)
    end

    # Evaluate rules for a set of ref_updates
    #
    # repository              - The repository to evaluate rules on
    # ref_updates             - The ref_updates being proposed
    # actor                   - The actor proposing the ref_updates
    # metadata_source         - (Optional) source for Spokes-related data (used for testing)
    # dry_run                 - Whether the result of this run will be commited
    # phase                   - Phase of the evaluation used to determine which rules are evaluated. Defaults to PostReceive, which only evaluates ref rules.
    # options                 - {
    #  :server_merge - Boolean indicating whether this run uses a server-generated merge commit as the after_oid
    #  :fetch_and_merge - Boolean indicating whether this run is for a fork sync operation
    #  :pre_receive_rule_suites - Array of RuleSuites that were generated during the pre-receive phase (required when evaluating the post-receive phase)
    #  :commit_refs_evaluation - Boolean indicating whether this run is evaluated during GitAuth's commit_refs
    # }
    #
    # Returns array of RuleSuites containing the results of for each ref_update
    sig do
      params(
        repository: Repository,
        ref_updates: T::Array[Git::Ref::Update],
        actor: RuleEngine::Types::Actor,
        phase: T.nilable(Types::Phase),
        metadata_source: T.nilable(RuleEngine::MetadataSources::Base),
        dry_run: T::Boolean,
        options: T::Hash[Symbol, T.untyped]
      ).returns(T::Array[RuleSuite])
    end
    def self.evaluate_rules(repository,
                            ref_updates,
                            actor,
                            phase: RuleEngine::Types::Phase::PostReceive,
                            metadata_source: nil,
                            dry_run: false,
                            options: {})
      return [] if ref_updates.size == 0

      event = if dry_run
        Events::MergeBoxQueryEvent.new(repository, ref_updates, actor)
      elsif phase == Types::Phase::PreReceive
        Events::PreReceivePushEvent.new(repository, ref_updates, actor,
          metadata_source: metadata_source || RuleEngine::MetadataSources::Spokes.new,
          commit_refs: options[:commit_refs_evaluation] || false)
      else
        Events::PostReceivePushEvent.new(repository, ref_updates, actor,
          metadata_source: metadata_source || RuleEngine::MetadataSources::Spokes.new,
          commit_refs: options[:commit_refs_evaluation] || false,
          pre_receive_rule_suites: options[:pre_receive_rule_suites] || [],
          server_merge: options[:server_merge] || false,
          fetch_and_merge: options[:fetch_and_merge] || false,
          quarantine_disabled: phase.nil?
        )
      end

      GenericEvaluator.evaluate_rules(event)
    end

    # Evaluate rules before a commit has been created
    #
    # repository              - The repository to evaluate runs on
    # target                  - The proposed parent commit OID, or nil for a new tree
    # actor                   - The actor proposing the commit
    # metadata                - The metadata of the commit being proposed {
    #  :message - String defining the message for the commit
    #  :author_email - String defining the author's email
    #  :committer_email - String defining the committer's email
    #  :blobs - Hash of blob paths to contents
    # }
    # target_ref_name         - (Optional) fully qualified name of the ref that point to the new commit
    sig do
      params(
        repository: Repository,
        target: T.nilable(String),
        actor: RuleEngine::Types::Actor,
        metadata: {
          message: T.nilable(String),
          author_email: T.nilable(String),
          committer_email: T.nilable(String),
          blobs: T::Hash[String, T.nilable(String)]
        },
        target_ref_name: T.nilable(String)
      ).returns(RuleSuite)
    end
    def self.evaluate_pre_commit_rules(repository, target, actor, metadata, target_ref_name: nil)
      event = Events::PreCommitEvent.new(repository, actor, target:, metadata:, target_ref_name:)

      T.must(GenericEvaluator.evaluate_rules(event).first)
    end

    # Public: Get the rule object for the given rule type
    #
    # rule_type - The string push policy type
    #
    # Returns a BaseRule object
    sig { params(rule_type: String).returns(T.nilable(RuleEngine::BaseRule)) }
    def self.rule_impl_for_rule_type(rule_type)
      REGISTERED_RULES[rule_type] || COMPANION_RULES[rule_type]
    end
  end
end
