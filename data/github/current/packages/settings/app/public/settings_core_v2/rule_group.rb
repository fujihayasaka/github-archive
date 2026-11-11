# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Optional UI feature that allows many rules to share a single ConditionExpression
  class RuleGroup
    sig { returns(T.untyped) }
    attr_reader :resource

    sig { returns(IConditionExpression) }
    attr_reader :condition_expression

    sig { returns(T::Array[[String, IRule]]) }
    attr_reader :rules

    sig { params(resource: T.untyped, condition_expression: IConditionExpression, rules: T::Array[[String, IRule]]).void }
    def initialize(resource, condition_expression, rules)
      @resource = resource
      @condition_expression = condition_expression
      @rules = rules
    end

    sig { params(settings: T::Array[ISetting]).returns(T::Array[RuleGroup]) }
    def self.from_settings(settings)
      groups_by_resource = settings.group_by(&:resource)
      groups_by_resource.flat_map do |resource, resource_settings|
        all_rules = resource_settings.flat_map { |s| s.rules }
        all_rules.group_by(&:condition_expression).map do |condition_expression, rules|
          rules_with_setting_name = rules.filter_map do |rule|
            if (setting_name = rule.setting&.name)
              [setting_name, rule]
            end
          end
          new(resource, condition_expression, rules_with_setting_name)
        end
      end
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def serialize
      {
        conditionExpressionId: condition_expression.id,
        conditionExpression: condition_expression.serialize,
        rules: rules.map { |setting_name, rule| rule.serialize.merge({ settingName: setting_name }) },
      }
    end

    sig { params(resource: T.untyped, hash: T::Hash[String, T.untyped]).returns(RuleGroup) }
    def self.deserialize(resource, hash)
      condition_expression = MemoryConditionExpression.from_hash(hash.fetch("conditionExpression"))
      rules = hash.fetch("rules").map do |rule_hash|
        setting_name = rule_hash.fetch("settingName")
        rule_hash["conditionExpression"] = hash.fetch("conditionExpression")
        rule = MemoryRule.from_hash(rule_hash.except("settingName"))
        [setting_name, rule]
      end
      RuleGroup.new(resource, condition_expression, rules)
    end
  end
end
