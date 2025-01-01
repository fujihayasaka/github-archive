# typed: strict
# frozen_string_literal: true

module Configurable
  module CodeScanningAutofix
    extend T::Helpers

    requires_ancestor { Configurable }

    CODE_SCANNING_AUTOFIX_ENABLEMENT_KEY = "code_scanning_autofix.enablement"

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def enable_code_scanning_autofix_settings(actor:)
      config.enable(CODE_SCANNING_AUTOFIX_ENABLEMENT_KEY, actor)
    end

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def disable_code_scanning_autofix_settings(actor:)
      config.disable(CODE_SCANNING_AUTOFIX_ENABLEMENT_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def code_scanning_autofix_settings_enabled?
      value = config.get(CODE_SCANNING_AUTOFIX_ENABLEMENT_KEY)

      # Default value
      return true if value.nil?

      value == Configuration::TRUE
    end

    CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ENABLEMENT_KEY = "code_scanning_autofix_third_party_tools.enablement"

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def enable_code_scanning_autofix_third_party_tools_settings(actor:)
      config.enable(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ENABLEMENT_KEY, actor)
    end

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def disable_code_scanning_autofix_third_party_tools_settings(actor:)
      config.disable(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ENABLEMENT_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def code_scanning_autofix_third_party_tools_settings_enabled?
      value = config.get(CODE_SCANNING_AUTOFIX_THIRD_PARTY_TOOLS_ENABLEMENT_KEY)

      # Default value
      return true if value.nil?

      value == Configuration::TRUE
    end
  end
end
