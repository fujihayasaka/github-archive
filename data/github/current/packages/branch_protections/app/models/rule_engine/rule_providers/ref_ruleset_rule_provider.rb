# typed: true
# frozen_string_literal: true

module RuleEngine
  module RuleProviders
    class RefRulesetRuleProvider < GitRulesetRuleProvider

      def initialize
        super(identifier: "ref_ruleset")
      end

      sig { override.returns(Types::Phase) }
      def phase
        Types::Phase::PostReceive
      end

      sig { override.params(repository: Repository).returns(T::Array[RepositoryRuleset]) }
      def load_rulesets(repository)
        return [] unless repository.supports_protected_branches?
        RepositoryRuleset.load_for(source: repository, include_parents: true, targets: %w(branch tag), check_conditions_on_parent_rulesets: false)
      end
    end
  end
end
