# typed: true
# frozen_string_literal: true

module Configurable
  module CodeScanning
    extend T::Helpers
    include Configurable::CodeScanningSeverities
    requires_ancestor { Configurable }

    def set_code_scanning_severity_choice(choice:, actor:)
      if SEVERITY_CHOICES.include?(choice)
        config.set(SEVERITY_CHOICE_KEY, choice, actor)
      end
    end

    def code_scanning_severity_choice
      # Default to errors only if no config is set
      config.get(SEVERITY_CHOICE_KEY) || SEVERITY_CHOICE_ERRORS
    end

    def set_code_scanning_security_severity_choice(choice:, actor:)
      if SECURITY_SEVERITY_CHOICES.include?(choice)
        config.set(SECURITY_SEVERITY_CHOICE_KEY, choice, actor)
      end
    end

    def code_scanning_security_severity_choice
      # Default to high and higher only if no config is set
      config.get(SECURITY_SEVERITY_CHOICE_KEY) || SECURITY_SEVERITY_HIGH_OR_HIGHER
    end

    CODE_SCANNING_DELEGATED_ALERT_DISMISSAL_ENABLEMENT_KEY = "code_scanning_delegated_alert_dismissal.enablement"

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def enable_code_scanning_delegated_alert_dismissal_settings(actor:)
      config.enable(CODE_SCANNING_DELEGATED_ALERT_DISMISSAL_ENABLEMENT_KEY, actor)
    end

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def disable_code_scanning_delegated_alert_dismissal_settings(actor:)
      config.disable(CODE_SCANNING_DELEGATED_ALERT_DISMISSAL_ENABLEMENT_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def code_scanning_delegated_alert_dismissal_settings_enabled?
      value = config.get(CODE_SCANNING_DELEGATED_ALERT_DISMISSAL_ENABLEMENT_KEY)

      # Default value
      return false if value.nil?

      value == Configuration::TRUE
    end
  end
end
