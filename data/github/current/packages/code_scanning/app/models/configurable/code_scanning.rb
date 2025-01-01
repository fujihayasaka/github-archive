# typed: true
# frozen_string_literal: true

module Configurable
  module CodeScanning
    extend T::Helpers
    requires_ancestor { Configurable }
    requires_ancestor { Kernel }
    requires_ancestor { CodeScanningRepositoryConfig }

    UPLOAD_ENDPOINT_DISABLED_KEY = "code_scanning.upload_endpoint_disabled"

    SEVERITY_CHOICE_KEY = "code_scanning.severity_choice"
    SEVERITY_CHOICE_NONE = "none".freeze
    SEVERITY_CHOICE_ERRORS = "errors".freeze
    SEVERITY_CHOICE_ERRORS_AND_WARNINGS = "errors_and_warnings".freeze
    SEVERITY_CHOICE_ALL = "all".freeze
    SEVERITY_CHOICES = [SEVERITY_CHOICE_NONE, SEVERITY_CHOICE_ERRORS, SEVERITY_CHOICE_ERRORS_AND_WARNINGS, SEVERITY_CHOICE_ALL]

    SECURITY_SEVERITY_CHOICE_KEY = "code_scanning.security_severity_choice"
    SECURITY_SEVERITY_NONE = "none".freeze
    SECURITY_SEVERITY_CRITICAL = "critical".freeze
    SECURITY_SEVERITY_HIGH_OR_HIGHER = "high".freeze
    SECURITY_SEVERITY_MEDIUM_OR_HIGHER = "medium".freeze
    SECURITY_SEVERITY_ALL = "all".freeze
    SECURITY_SEVERITY_CHOICES = [SECURITY_SEVERITY_NONE, SECURITY_SEVERITY_CRITICAL, SECURITY_SEVERITY_HIGH_OR_HIGHER, SECURITY_SEVERITY_MEDIUM_OR_HIGHER, SECURITY_SEVERITY_ALL]

    def enable_code_scanning_upload_endpoint(actor:)
      config.delete(UPLOAD_ENDPOINT_DISABLED_KEY, actor)
    end

    def disable_code_scanning_upload_endpoint(actor:)
      config.enable(UPLOAD_ENDPOINT_DISABLED_KEY, actor)
    end

    def code_scanning_upload_endpoint_disabled?
      config.enabled?(UPLOAD_ENDPOINT_DISABLED_KEY)
    end

    # Indicates if the code scanning upload endpoint is available to serve requests
    def code_scanning_upload_endpoint_available?
      !code_scanning_upload_endpoint_disabled?
    end

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
