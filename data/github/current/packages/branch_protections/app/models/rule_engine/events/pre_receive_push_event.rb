# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class PreReceivePushEvent < GitEvent

      sig do
        params(
          repository: Repository,
          ref_updates: T::Array[Git::Ref::Update],
          actor: Types::Actor,
          metadata_source: T.nilable(RuleEngine::MetadataSources::Base),
          commit_refs: T::Boolean
        ).void
      end
      def initialize(repository, ref_updates, actor, metadata_source: nil, commit_refs: false)
        super(
          repository,
          ref_updates,
          actor,
          metadata_source: metadata_source || RuleEngine::MetadataSources::Spokes.new,
          phase: RuleEngine::Types::Phase::PreReceive,
          commit_refs:)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        {
          merge_box_evaluation: false,
          commit_refs_evaluation: commit_refs?,
          server_merge: false,
          fetch_and_merge: false
        }
      end

      sig { override.params(rule_configs: T::Array[RepositoryRuleConfiguration]).returns(T::Array[RepositoryRuleConfiguration]) }
      def before_evaluation(rule_configs)
        return super unless rule_configs.any? { |rule_config| rule_config.provider_name == "push_ruleset" }
        return super unless repository.feature_enabled_for_repo_or_owner?(:push_rulesets_limit_refs)

        raise Errors::RefLimitReached.new if event_actions.size > RuleEngine::Errors::RefLimitReached::THRESHOLD

        super
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites.each do |suite|
          suite.evaluation_metadata.merge!(pull_request_metadata(suite.ref_update))
        end

        # If we're in the pre-receive phase, we need to fail all ref_updates if any of the ref_updates failed
        if !rule_suites.all?(&:action_permitted?)
          rule_suites.each do |suite|
            suite.evaluation_metadata["pre_receive_failure"] = true
            suite.result = :push_rejected if suite.allowed?
          end
        end

        rule_suites + skipped_ref_updates.map { |ref_update| RuleSuite.success(repository, ref_update, actor) }
      end

      sig { override.params(rule_suites: T::Array[RuleEngine::RuleSuite]).void }
      def record_results(rule_suites)
        super

        GitHub.context.push(repository_rules_engine_pre_receive_rule_suites: rule_suites.map(&:id))
      end

      sig { override.params(exception: StandardError).returns(T::Array[RuleSuite]) }
      def handle_exception(exception)
        rule_suites = super(exception)
        ProtectedBranchLegacyInstrumenter.instrument_decision(rule_suites, repository)
        rule_suites
      end
    end
  end
end
