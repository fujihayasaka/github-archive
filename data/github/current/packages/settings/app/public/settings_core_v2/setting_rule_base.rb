# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module SettingRuleBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include IRule

    abstract!

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.all(SettingRuleBase::ClassMethods, T.class_of(ActiveRecord::Base)))

      belongs_to :setting, class_name: self.impl_payload.setting_class.name, inverse_of: :rules
      belongs_to :condition_expression, class_name: self.impl_payload.condition_class.name
    end

    sig { abstract.params(value: T.nilable(String)).void }
    def rule_type=(value); end

    sig { abstract.params(value: T.untyped).void }
    def parameters=(value); end

    sig { abstract.params(value: Integer).void }
    def priority=(value); end

    sig { params(new_rule: IRule).void }
    def update_from_interface(new_rule)
      self.rule_type = new_rule.rule_type
      self.parameters = new_rule.parameters
      self.priority = new_rule.priority
    end

    module ClassMethods
      include Kernel

      sig { returns(ImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "#{self.class.name} must implement impl_payload"
      end

      sig { params(rule: IRule, setting: SettingBase).returns(SettingRuleBase) }
      def create_from_interface(rule, setting)
        new_rule = T.cast(self, T.class_of(ActiveRecord::Base)).new
        new_rule.setting = setting
        new_rule.rule_type = rule.rule_type
        new_rule.parameters = rule.parameters
        new_rule.priority = rule.priority
        if rule.condition_expression.id
          new_rule.condition_expression_id = rule.condition_expression.id
        else
          new_rule.condition_expression = impl_payload.condition_class.create_from_interface(rule.condition_expression)
        end

        new_rule
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
