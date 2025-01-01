# typed: strict
# frozen_string_literal: true

module RuleEngine
  module Events
    class PostReceivePushEvent < GitEvent
      include GitHub::Memoizer

      sig do
        params(
          repository: Repository,
          ref_updates: T::Array[Git::Ref::Update],
          actor: Types::Actor,
          metadata_source: T.nilable(RuleEngine::MetadataSources::Base),
          pre_receive_rule_suites: T.nilable(T::Array[RuleSuite]),
          commit_refs: T::Boolean,
          server_merge: T::Boolean,
          fetch_and_merge: T::Boolean,
          quarantine_disabled: T::Boolean,
        ).void
      end
      def initialize(repository, ref_updates, actor, metadata_source: nil,
        pre_receive_rule_suites: nil,
        commit_refs: false,
        server_merge: false,
        fetch_and_merge: false,
        quarantine_disabled: false)
        super(
          repository,
          ref_updates,
          actor,
          metadata_source: metadata_source || RuleEngine::MetadataSources::Spokes.new,
          phase: RuleEngine::Types::Phase::PostReceive,
          commit_refs:)

        @pre_receive_rule_suites = pre_receive_rule_suites

        @server_merge = server_merge
        @fetch_and_merge = fetch_and_merge
        @quarantine_disabled = quarantine_disabled
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def additional_context
        {
          merge_box_evaluation: false,
          commit_refs_evaluation: commit_refs?,
          server_merge: @server_merge,
          fetch_and_merge: @fetch_and_merge
        }
      end

      # When quarantine is disabled, post receive runs all rules
      sig { returns(T::Boolean) }
      def quarantine_disabled?
        @quarantine_disabled
      end

      sig { override.params(rule_suites: T::Array[RuleSuite]).returns(T::Array[RuleSuite]) }
      def finalize_rule_suites(rule_suites)
        pre_receive_rule_suites_by_ref_update = (self.pre_receive_rule_suites || []).index_by { |suite| suite.ref_name }

        merged_suites = rule_suites.map do |suite|
          ref_update = suite.ref_update

          if !pre_receive_rule_suites_by_ref_update.key?(ref_update.refname) && !pre_receive_rule_suites_by_ref_update.key?(GitHub::UNKNOWN_REF_NAME)
            suite.evaluation_metadata.merge!(pull_request_metadata(suite.ref_update))
            next suite
          end

          pre_receive_rule_suite = pre_receive_rule_suites_by_ref_update[ref_update.refname] || pre_receive_rule_suites_by_ref_update[GitHub::UNKNOWN_REF_NAME]
          RuleSuite.merge(suite: pre_receive_rule_suite, ref_update: ref_update, rule_runs: suite.rule_runs, actor: actor)
        end

        merged_suites + skipped_ref_updates.map { |ref_update| RuleSuite.success(repository, ref_update, actor) }
      end

      sig { override.params(exception: StandardError).returns(T::Array[RuleSuite]) }
      def handle_exception(exception)
        rule_suites = super(exception)
        ProtectedBranchLegacyInstrumenter.instrument_decision(rule_suites, repository)
        rule_suites
      end

      private

      sig { returns(T.nilable(T::Array[RuleSuite])) }
      memoize def pre_receive_rule_suites
        return @pre_receive_rule_suites if @pre_receive_rule_suites.present?

        if GitHub.context[:repository_rules_engine_pre_receive_rule_suites].present?
          ids = GitHub.context[:repository_rules_engine_pre_receive_rule_suites]
          GitHub.context.push(repository_rules_engine_pre_receive_rule_suites: nil)

          RuleEngine::RuleSuite.where(id: ids).to_ary
        end
      end
    end
  end
end
