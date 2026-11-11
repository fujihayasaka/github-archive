# typed: strict
# frozen_string_literal: true

# Shared deprecation constants for Copilot metrics API sunset
# See: https://github.blog/changelog/2026-01-29-closing-down-notice-of-legacy-copilot-metrics-apis/
module Api::CopilotForBusiness::DeprecationConstants
  # Common deprecation information
  DEPRECATION_INFO_URL = "https://github.blog/changelog/2026-01-29-closing-down-notice-of-legacy-copilot-metrics-apis/"
  DEPRECATION_DATE = T.let(Time.utc(2026, 1, 29), Time)

  # Metrics API sunsets April 2, 2026
  SUNSET_DATE_APRIL = T.let(Time.utc(2026, 4, 2), Time)
end
