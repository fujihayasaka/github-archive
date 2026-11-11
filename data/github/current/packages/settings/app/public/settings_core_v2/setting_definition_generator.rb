# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Base class for defining dynamic settings
  # Use when either:
  #   1. Settings are defined by attributes stored in a DB (ex: Copilot registry models)
  #   2. Many settings have the same definition except for a small number of attributes
  class SettingDefinitionGenerator
    extend T::Helpers

    abstract!

    sig { params(prefix: String).void }
    def initialize(prefix)
      @prefix = prefix
    end

    sig { params(setting_name: String).returns(T::Boolean) }
    def matches?(setting_name)
      # Only match setting names that start with the prefix and don't have additional dot notation
      setting_name.start_with?(@prefix) && !setting_name.delete_prefix(@prefix).include?(".")
    end

    sig { abstract.params(setting_name: String).returns(SettingDefinition[T.untyped, T.untyped]) }
    def generate_definition(setting_name); end

    sig { overridable.params(resource: T.untyped).returns(T::Array[String]) }
    def known_setting_names(resource = nil)
      []
    end
  end
end
