# typed: strict
# frozen_string_literal: true

module SettingsCore
  # An interface for loading settings from a data source.
  # Settings can contain rules that modify or validate the setting value during evaluation.
  class SettingsProvider
    extend T::Helpers

    abstract!

    sig { returns(String) }
    attr_reader :name

    sig { params(name: String).void }
    def initialize(name)
      @name = name
    end

    sig { abstract.params(names: T::Array[String], targetables: T::Array[Targeting::Targetable]).returns(T::Array[ISetting]) }
    def settings_for(names, targetables); end

    # Update or create a setting in the data source.
    # Returns the created or updated setting when successful, or nil if the update failed.
    sig { overridable.params(setting: ISetting, actor: T.nilable(User)).returns(T.nilable(ISetting)) }
    def update_setting(setting, actor: nil)
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
      end
    end
  end
end
