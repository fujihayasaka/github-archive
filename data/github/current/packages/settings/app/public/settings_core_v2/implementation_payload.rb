# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  class ImplementationPayload < T::Struct
    SettingsModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        SettingBase::ClassMethods,
        T::Class[T.all(ActiveRecord::Base, SettingBase)],
      )
    end

    RuleModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        SettingRuleBase::ClassMethods,
        T::Class[T.all(ActiveRecord::Base, SettingRuleBase)],
      )
    end

    ConditionsModelImpl = T.type_alias do
      T.all(
        T.class_of(ActiveRecord::Base),
        ConditionExpressionBase::ClassMethods,
        T::Class[T.all(ActiveRecord::Base, ConditionExpressionBase)],
      )
    end

    const :setting_class, SettingsModelImpl
    const :rule_class, RuleModelImpl
    const :condition_class, ConditionsModelImpl
  end
end
