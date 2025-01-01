# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Processors related to the BillingPlatform POC.
    module BillingPlatform
      autoload :UsageReportRequestNotificationProcessor, "github/stream_processors/billing_platform/usage_report_request_notification_processor"
      autoload :BudgetThresholdNotificationProcessor, "github/stream_processors/billing_platform/budget_threshold_notification_processor"
    end
  end
end
