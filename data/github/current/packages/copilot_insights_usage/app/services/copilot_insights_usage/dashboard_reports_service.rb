# typed: strict
# frozen_string_literal: true

# Fetches the cached 28-day dashboard report from the Copilot Usage Service.
# Mirrors the shape of Copilot::Metrics::UsageReport#fetch so the dashboard
# chart services can swap in this client without a contract change. See
# https://github.com/github/copilot-metrics/issues/2574.
class CopilotInsightsUsage::DashboardReportsService
  class Error < StandardError; end
  class RequestError < Error; end

  ENTERPRISE_PATH = "/enterprises/%{enterprise_id}/copilot/metrics/usage-data/28-day/latest"
  ORGANIZATION_PATH = "/organizations/%{organization_id}/copilot/metrics/usage-data/28-day/latest"

  sig do
    params(
      enterprise_id: Integer,
      client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)
    ).returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def self.fetch_enterprise_latest_28_day(enterprise_id:, client: nil)
    new(client: client).fetch_enterprise_latest_28_day(enterprise_id: enterprise_id)
  end

  sig do
    params(
      organization_id: Integer,
      enterprise_id: T.nilable(Integer),
      client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)
    ).returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def self.fetch_organization_latest_28_day(organization_id:, enterprise_id: nil, client: nil)
    new(client: client).fetch_organization_latest_28_day(
      organization_id: organization_id,
      enterprise_id: enterprise_id
    )
  end

  sig { params(client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)).void }
  def initialize(client: nil)
    @client = T.let(
      client || CopilotInsightsUsage::CopilotUsageServiceClient.new,
      CopilotInsightsUsage::CopilotUsageServiceClient
    )
  end

  sig do
    params(enterprise_id: Integer)
      .returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def fetch_enterprise_latest_28_day(enterprise_id:)
    path = format(ENTERPRISE_PATH, enterprise_id: enterprise_id)
    fetch_report(path: path, entity_type: "enterprise", entity_id: enterprise_id)
  end

  sig do
    params(organization_id: Integer, enterprise_id: T.nilable(Integer))
      .returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def fetch_organization_latest_28_day(organization_id:, enterprise_id: nil)
    path = format(ORGANIZATION_PATH, organization_id: organization_id)
    path = "#{path}?enterprise_id=#{enterprise_id}" if enterprise_id
    fetch_report(path: path, entity_type: "organization", entity_id: organization_id)
  end

  private

  sig do
    params(path: String, entity_type: String, entity_id: Integer)
      .returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def fetch_report(path:, entity_type:, entity_id:)
    resp = @client.connection.get(path)

    if resp.status == 404
      GitHub.logger.info(
        "No dashboard report available from Copilot Usage Service (404)",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "gh.#{entity_type}.id": entity_id,
        "gh.request.path": path
      )
      return nil
    end

    unless resp.success?
      GitHub.logger.error(
        "Failed to fetch dashboard report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "gh.#{entity_type}.id": entity_id,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body,
        "gh.request.path": path
      )
      raise RequestError, "Copilot Usage Service returned #{resp.status} for #{path}"
    end

    parse_body(resp.body, entity_type: entity_type, entity_id: entity_id, path: path)
  end

  sig do
    params(body: T.untyped, entity_type: String, entity_id: Integer, path: String) # rubocop:disable Sorbet/ForbidTUntyped
      .returns(T.nilable(T::Hash[String, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
  end
  def parse_body(body, entity_type:, entity_id:, path:)
    parsed = body
    if parsed.is_a?(String)
      begin
        parsed = GitHub::JSON.parse(parsed)
      rescue StandardError => e
        GitHub.logger.error(
          "Failed to parse JSON response from Copilot Usage Service",
          "code.namespace": self.class.name,
          "code.function": __method__.to_s,
          "gh.#{entity_type}.id": entity_id,
          "exception.class": e.class.name,
          "exception.message": e.message,
          "gh.request.path": path
        )
        raise RequestError, "Failed to parse Copilot Usage Service response: #{e.message}"
      end
    end
    unless parsed.is_a?(Hash)
      raise RequestError, "Copilot Usage Service returned #{parsed.class.name} instead of Hash for #{path}"
    end
    parsed
  end
end
