# typed: strict
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    module GitRuleProvider
      extend T::Sig
      extend T::Helpers
      abstract!

      sig do
        params(
          event: RuleEvent
        ).returns(T::Array[RepositoryRuleConfiguration])
      end
      def rules_for_event(event)
        return [] unless event.is_a?(GitEvent)
        return [] unless event.phase == phase || (event.is_a?(Events::PostReceivePushEvent) && event.quarantine_disabled?)

        configs = rules_for_ref_updates(event.repository, event.event_actions, event.actor)
        configs.each do |config|
          config.matching_event_actions = config.matching_ref_names.flat_map do |ref_name|
            event.event_actions.filter { |action| action.refname == ref_name }
          end.uniq
        end

        configs
      end

      sig { overridable.returns(Types::Phase) }
      def phase
        Types::Phase::PostReceive
      end

      # Called during evaluation to discover the rules that apply to the given ref updates.
      # repository - A Repository
      # ref_updates - An array of RefUpdate
      # actor - An Actor (or nil)
      #
      # Returns an array of RepositoryRuleConfigurations
      sig { abstract.params(repository: Repository, ref_updates: T::Array[Git::Ref::Update], actor: T.nilable(Types::Actor)).returns(T::Array[RepositoryRuleConfiguration]) }
      def rules_for_ref_updates(repository, ref_updates, actor); end

      # Called outside of evaluation to discover the rules that apply to the given ref (used by the branch evaluator).
      # repository - A Repository
      # ref_name - A fully qualified ref name
      #
      # Returns an array of RepositoryRuleConfigurations
      sig { abstract.params(repository: Repository, ref_names: T::Array[String]).returns(T::Array[RepositoryRuleConfiguration]) }
      def rule_for_branch_evaluators(repository, ref_names); end
    end
  end
end
