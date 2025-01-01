# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class MemberPrivilegeRulesetRuleProvider < RulesetRuleProvider

      def initialize
        super(identifier: "member_privilege_ruleset")
      end

      sig { override.params(event: RepositoryEvent).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets_for_event(event)
        return [] unless event.repository.member_privilege_rulesets_enabled?
        return [] unless event.is_a?(Events::RepositoryOperationEvent)

        RepositoryRuleset.load_for(source: event.repository, include_parents: true, targets: ["member_privilege"])
      end
    end
  end
end
