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

      sig { override.params(repository: Repository).returns(T::Array[IRuleset]) }
      def load_rulesets(repository)
        return [] unless repository.supports_protected_branches?
        sources = Repositories.domain.rulesets.inherited_sources(repository, "branch") + [repository]
        Repositories.domain.rulesets.load_rulesets_for_sources(sources, targets: %w(branch tag))
      end
    end
  end
end
