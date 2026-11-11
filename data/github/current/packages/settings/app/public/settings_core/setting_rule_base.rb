# typed: strict
# frozen_string_literal: true

module SettingsCore
  module SettingRuleBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include IRule

    abstract!

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.all(SettingRuleBase::ClassMethods, T.class_of(ActiveRecord::Base)))

      belongs_to :setting, class_name: self.setting_class_name, inverse_of: :rules
      belongs_to :condition_expression, class_name: self.condition_class_name
    end

    sig { params(new_rule: IRule).void }
    def update_from_interface(new_rule)
      T.unsafe(self).rule_type = new_rule.rule_type
      T.unsafe(self).parameters = new_rule.parameters
    end

    module ClassMethods
      include Kernel

      sig { returns(String) }
      def setting_class_name
        raise NotImplementedError, "#{self.class.name} must implement setting_class_name"
      end

      sig { returns(String) }
      def condition_class_name
        raise NotImplementedError, "#{self.class.name} must implement condition_class_name"
      end

      sig { params(rule: IRule, setting: SettingBase).returns(SettingRuleBase) }
      def create_from_interface(rule, setting)
        new_rule = T.cast(self, T.class_of(ActiveRecord::Base)).new
        new_rule.setting = setting
        new_rule.rule_type = rule.rule_type
        new_rule.parameters = rule.parameters
        new_rule.condition_expression = condition_class_name.constantize.create_from_interface(rule.condition_expression)

        new_rule
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
