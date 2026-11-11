# typed: true
# frozen_string_literal: true

class CopilotInsightsUsage::CopilotUsageServiceClient < CopilotInsightsUsage::Api
  def initialize(url: GitHub.copilot_usage_service_url, hmac_key: GitHub.copilot_usage_service_hmac_key, connection_timeout: 10)
    super
  end
end
