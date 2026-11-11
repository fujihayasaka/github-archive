# typed: strict
# frozen_string_literal: true

module Configurable
  module CodeScanningAiFindings
    extend T::Helpers

    requires_ancestor { Configurable }

    CODE_SCANNING_AI_FINDINGS_ENABLEMENT_KEY = "code_scanning_ai_findings.enablement"

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def enable_code_scanning_ai_findings_settings(actor:)
      config.enable(CODE_SCANNING_AI_FINDINGS_ENABLEMENT_KEY, actor)
    end

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def disable_code_scanning_ai_findings_settings(actor:)
      config.disable(CODE_SCANNING_AI_FINDINGS_ENABLEMENT_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def code_scanning_ai_findings_settings_enabled?
      value = config.get(CODE_SCANNING_AI_FINDINGS_ENABLEMENT_KEY)
      value == Configuration::TRUE
    end
  end
end
