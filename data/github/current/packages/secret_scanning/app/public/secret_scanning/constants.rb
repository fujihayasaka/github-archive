# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Constants
    # app name for reporting errors to failbot
    # this controls the application name in Sentry, and show up under the `application` field in splunk prod-exceptions
    FAILBOT_APP_NAME = "github"

    # DEPRECATED: Use SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE instead
    EXEMPTION_REQUEST_TYPE = ::SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_TYPE

    # The key for the scan result in the RuleRun evaluation metadata.
    # Used by SecretScanningRule and SecretScanningRuleProvider.
    RULE_RUN_SCAN_RESULT_METADATA_KEY = "scan_result"

    # The key for the content scan result in the RuleRun evaluation metadata.
    # Used by SecretScanningContentScanRule.
    CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY = "scan_results"

    # These are temporary constants used by SecretScanningRuleProvider, to bypass push protection for certain
    # OpenAI apps. https://github.com/github/secret-scanning/issues/13566
    OPENAI_ORG_ID = 14957082
    OPENAI_APP_IDS = [1193682, 1198827]

    class SelfServeBannerSlugs
      SECRET_PROTECTION_FEEDBACK_SURVEY = "secret-protection-feedback-survey"
    end
  end
end
