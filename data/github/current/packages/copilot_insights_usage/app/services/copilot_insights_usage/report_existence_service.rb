# typed: strict
# frozen_string_literal: true

class CopilotInsightsUsage::ReportExistenceService
  sig do
    params(
      enterprise_id: Integer,
      report_type: String,
      day: T.any(Date, String),
      client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient),
    ).returns(Symbol)
  end
  def self.check(enterprise_id:, report_type:, day:, client: nil)
    new(client: client).check(
      enterprise_id: enterprise_id,
      report_type: report_type,
      day: day,
    )
  end

  sig { params(client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)).void }
  def initialize(client: nil)
    @client = T.let(
      client || CopilotInsightsUsage::CopilotUsageServiceClient.new,
      CopilotInsightsUsage::CopilotUsageServiceClient,
    )
  end

  sig do
    params(
      enterprise_id: Integer,
      report_type: String,
      day: T.any(Date, String),
    ).returns(Symbol)
  end
  def check(enterprise_id:, report_type:, day:)
    path = "/enterprises/#{enterprise_id}/copilot/metrics/reports/#{report_type}"
    resp = @client.connection.get(path, { day: day.to_s })

    return :exists if resp.success?

    if resp.status == 404
      GitHub.logger.info(
        "Copilot Metrics Report does not exist for the requested day",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "gh.enterprise.id": enterprise_id,
        "gh.copilot.report_type": report_type,
        "gh.requested_day": day.to_s,
      )
      return :missing
    end

    GitHub.logger.error(
      "Failed to verify Copilot Metrics Report existence",
      "code.namespace": self.class.name,
      "code.function": __method__.to_s,
      "gh.enterprise.id": enterprise_id,
      "gh.copilot.report_type": report_type,
      "gh.requested_day": day.to_s,
      "gh.http.status": resp.status,
    )
    :error
  rescue Faraday::Error => e
    GitHub.logger.error(
      "Error contacting Copilot Usage Service to verify report existence",
      "code.namespace": self.class.name,
      "code.function": __method__.to_s,
      "gh.enterprise.id": enterprise_id,
      "gh.copilot.report_type": report_type,
      "gh.requested_day": day.to_s,
      "error.class": e.class.name,
      "error.message": e.message,
    )
    :error
  end
end
