# typed: strict
# frozen_string_literal: true

module Actions
  class Domain
    class Rulesets < GH::Domain::Base
      extend T::Generic
      include RuleEngine::DomainAccessorBase

      RuleSource = type_member { { fixed: T.any(Repository, Organization, Business) } }

      register_rule_implementation(RuleEngine::Rules::RestrictActionsActorsRule.new)
      register_rule_implementation(RuleEngine::Rules::RestrictActionsEventsRule.new)

      register_rule_provider(ActionsRules::ActionsRulesetRuleProvider.new)
      register_rule_provider(RuleEngine::RuleProviders::ImplicitPullRequestTargetRuleProvider.new)

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
      # Returns the maximum number of rulesets allowed for the given source.
      sig { override.params(source: RuleSource).returns(Integer) }
      def ruleset_limit(source)
        RULESET_LIMIT
      end

      # Returns the sources from which the given source can inherit rulesets.
      sig { override.params(source: T.untyped, target: String).returns(T::Array[RuleSource]) }
      def inherited_sources(source, target) # rubocop:disable Metrics/MethodLength
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

      # ActiveRecord class for rulesets in the Actions cluster.
      sig { override.returns(RuleEngine::DomainAccessorBase::RulesetClassType) }
      def ruleset_class
        ActionsRules::ActionsRuleset
      end
    end
  end
end
