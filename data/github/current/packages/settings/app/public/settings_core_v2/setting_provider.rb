# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Abstraction around setting and rule loading / saving
  class SettingProvider
    extend T::Helpers

    abstract!

    sig { returns(String) }
    attr_reader :name

    sig { params(name: String).void }
    def initialize(name)
      @name = name
    end

    sig { abstract.params(targets_to_names: T::Hash[T.untyped, T::Array[String]]).returns(T::Array[ISetting]) }
    def settings_for(targets_to_names); end

    # Update or create a setting in the data source.
    # Returns the created or updated setting when successful, or nil if the update failed.
    sig { overridable.params(resource: T.untyped, settings: T::Array[ISetting], actor: T.nilable(User)).returns(T::Array[ISetting]) }
    def update_settings(resource, settings, actor: nil)
      raise NotImplementedError, "This provider does not support updating settings"
    end

    sig { overridable.returns(T::Array[Features]) }
    def supported_features
      []
    end

    class Features < T::Enum
      enums do
        WRITE_SETTINGS = new("write_settings")
        WRITE_RULES = new("write_rules")
        RULE_GROUPS = new("write_rule_groups")
      end
    end
  end
end
