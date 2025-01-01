# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/copilot/v3/copilot_premium_usage_report_pb"

class HydroCopilotPremiumUsageReportJob < HydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_copilot_premium_usage_report

  retry_on_dirty_exit

  # Processes a premium usage report message and sends an email to the user with a download link to the report.
  sig { void }
  def perform
    GitHub.logger.with_named_tags(
      {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.user.id": payload.user_id,
        "gh.premium_usage_report.download_url": payload.download_url,
      }
    ) do
      user = ::User.find_by(id: payload.user_id)
      if user.nil?
        GitHub.logger.error("exception.message": "User not found for premium usage report")
        return
      end

      if !user.feature_enabled?(:copilot_premium_usage_report_email)
        GitHub.logger.info("User does not have the copilot_premium_usage_report_email feature flag enabled")
        return
      end

      if payload.download_url.nil? || payload.download_url == ""
        GitHub.logger.info("Download URL is empty, queueing mailer to send no data email")
        CopilotGeneralMailer.premium_usage_report_no_data(user).deliver_later
      else
        GitHub.logger.info("Queueing mailer to send premium usage report via email")
        CopilotGeneralMailer.premium_usage_report(user, payload.download_url).deliver_later
      end
    end
  end

  sig { returns(::Hydro::Schemas::Github::Copilot::V3::CopilotPremiumUsageReport) }
  memoize def payload
    ::Hydro::Schemas::Github::Copilot::V3::CopilotPremiumUsageReport.new(message)
  end
end
