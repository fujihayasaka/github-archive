# typed: true
# frozen_string_literal: true

module RuleEngine
  class Evaluator
    extend RuleEngine::Timing

    # Evaluate rules for a single ref_update
    #
    # repository              - The repository to evaluate rules on
    # ref_update              - The ref_update being proposed
    # actor                   - The actor proposing the ref_update
    # metadata_source         - (Optional) source for Spokes-related data (used for testing)
    # dry_run                 - Whether the result of this run will be commited
    # phase                   - Phase of the evaluation used to determine which rules are evaluated. Defaults to PostReceive, which only evaluates ref rules.
    # options                 - {
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
  end
end
