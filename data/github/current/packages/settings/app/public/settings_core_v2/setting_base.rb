# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module SettingBase
    extend ActiveSupport::Concern
    extend T::Helpers
    include ISetting

    abstract!

    requires_ancestor { ActiveRecord::Base }

    included do
      T.bind(self, T.all(SettingBase::ClassMethods, T.class_of(ActiveRecord::Base)))

      belongs_to :resource, polymorphic: true
      has_many :rules, class_name: impl_payload.rule_class.name, foreign_key: "setting_id", dependent: :delete_all, inverse_of: :setting
    end

    sig { abstract.params(value: T.untyped).void }
    def value=(value); end

    sig { params(new_setting: ISetting).void }
    def update_from_interface(new_setting)
      self.value = new_setting.value
    end

    module ClassMethods
      include Kernel

      sig { returns(ImplementationPayload) }
      def impl_payload
        raise NotImplementedError, "#{self.class.name} must implement impl_payload"
      end

      sig { params(setting: ISetting, resource: ActiveRecord::Base).returns(SettingBase) }
      def create_from_interface(setting, resource)
        new_setting = T.cast(self, T.class_of(ActiveRecord::Base)).new
        new_setting.name = setting.name
        new_setting.resource = resource
        new_setting.value = setting.value
        new_setting.rules = setting.rules.map { |rule| impl_payload.rule_class.create_from_interface(rule, new_setting) }

        new_setting
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
