# typed: strict
# frozen_string_literal: true

module RuleEngine
  class Registry

    RulesetClassType = T.type_alias { T.all(RuleEngine::IRuleset::ClassMethods, T::Class[T.all(ActiveRecord::Base, RuleEngine::IRuleset)]) }

    @ruleset_class_by_target = T.let({}, T::Hash[String, RulesetClassType])

    sig do
      params(target: String, clazz: RulesetClassType).void
    end
    def self.register_ruleset_target(target, clazz)
      @ruleset_class_by_target[target] = clazz
    end

    sig { params(target: String).returns(RulesetClassType) }
    def self.ruleset_class_for_target(target)
      ruleset_class = @ruleset_class_by_target[target]
      raise ArgumentError, "No ruleset class registered for target: #{target}" unless ruleset_class
      ruleset_class
    end

    # Returns ruleset classes for the given targets
    sig { params(targets: T::Array[String]).returns(T::Array[RulesetClassType]) }
    def self.ruleset_classes_for_targets(targets)
      targets.map { |target| ruleset_class_for_target(target) }.uniq
    end

    # TODO: Find a better way to register these. Doing them in `config/initializers` causes issues
    RuleEngine::Registry.register_ruleset_target("branch", RepositoryRuleset)
    RuleEngine::Registry.register_ruleset_target("tag", RepositoryRuleset)
    RuleEngine::Registry.register_ruleset_target("push", RepositoryRuleset)
    RuleEngine::Registry.register_ruleset_target("repository", RepositoryRuleset)
    RuleEngine::Registry.register_ruleset_target("actions", ::Rules::ActionsRuleset)
  end
end
