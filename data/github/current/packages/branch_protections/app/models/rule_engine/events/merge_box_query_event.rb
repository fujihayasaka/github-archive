# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class MergeBoxQueryEvent < GitEvent
      extend T::Sig

      sig do
        params(
          repository: Repository,
          ref_updates: T::Array[Git::Ref::Update],
          actor: Types::Actor,
        ).void
      end
      def initialize(repository, ref_updates, actor)
        super(
          repository,
          ref_updates,
          actor,
          metadata_source: RuleEngine::MetadataSources::Spokes.new,
          phase: RuleEngine::Types::Phase::PostReceive,
          commit_refs: false,
          is_writing: false)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        {
          merge_box_evaluation: true,
          commit_refs_evaluation: false,
          server_merge: false,
          fetch_and_merge: false
        }
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        rule_suites.each do |suite|
          suite.evaluation_metadata.merge!(pull_request_metadata(suite.ref_update))
        end

        rule_suites + skipped_ref_updates.map { |ref_update| RuleSuite.success(repository, ref_update, actor) }
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).void }
      def record_results(rule_suites)
        # Don't save suites or produce logs for merge box events
      end

      # overriden so we don't publish telemetry on failure
      sig { override.params(exception: StandardError).returns(T::Array[RuleSuite]) }
      def handle_exception(exception)
        raise exception unless exception.is_a?(GitRPC::ObjectMissing)

        rule_suites = (event_actions + skipped_ref_updates).map do |ref_update|
          RuleSuite.object_missing(repository, actor, ref_update: ref_update)
        end

        rule_suites
      end
    end
  end
end
