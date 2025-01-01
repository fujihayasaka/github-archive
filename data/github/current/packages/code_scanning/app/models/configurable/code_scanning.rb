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
  end
end
