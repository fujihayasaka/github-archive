# typed: strict
# frozen_string_literal: true

class CopilotInsightsUsage::ReportDownloadService
  sig do
    params(
      path: String,
      entity_id: Integer,
      entity_type: String,
      query: T::Hash[Symbol, String],
      client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)
    ).returns(T::Array[T::Hash[String, String]])
  end
  def self.fetch(path:, entity_id:, entity_type:, query: {}, client: nil)
    new(client: client).fetch(
      path: path,
      entity_id: entity_id,
      entity_type: entity_type,
      query: query
    )
  end

  sig { params(client: T.nilable(CopilotInsightsUsage::CopilotUsageServiceClient)).void }
  def initialize(client: nil)
    @client = T.let(client || CopilotInsightsUsage::CopilotUsageServiceClient.new, CopilotInsightsUsage::CopilotUsageServiceClient)
  end

  sig do
    params(
      path: String,
      entity_id: Integer,
      entity_type: String,
      query: T::Hash[Symbol, String]
    ).returns(T::Array[T::Hash[String, String]])
  end
  def fetch(path:, entity_id:, entity_type:, query: {})
    resp = @client.connection.get(path, query)

    unless resp.success?
      return handle_error(resp, path: path, entity_id: entity_id, entity_type: entity_type)
    end

    parse_download_links(resp.body, entity_id: entity_id, entity_type: entity_type, path: path)
  end

  private

  sig do
    params(
      resp: T.untyped,
      path: String,
      entity_id: Integer,
      entity_type: String
    ).returns(T::Array[T::Hash[String, String]])
  end
  def handle_error(resp, path:, entity_id:, entity_type:)
    if resp.status == 404
      GitHub.logger.info(
        "No report available from Copilot Usage Service (404)",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "gh.#{entity_type}.id": entity_id,
        "gh.request.path": path
      )
      return []
    end

    GitHub.logger.error(
      "Failed to fetch export files from Copilot Usage Service",
      "code.namespace": self.class.name,
      "code.function": __method__.to_s,
      "gh.#{entity_type}.id": entity_id,
      "gh.http.status": resp.status,
      "gh.response.body": resp.body,
      "gh.request.path": path
    )
    raise "Failed to fetch export files from Copilot Usage Service: #{resp.status} #{resp.body}"
  end

  sig do
    params(
      body: T.untyped,
      entity_id: Integer,
      entity_type: String,
      path: String
    ).returns(T::Array[T::Hash[String, String]])
  end
  def parse_download_links(body, entity_id:, entity_type:, path:)
    report = body

    if report.is_a?(String)
      begin
        parsed = GitHub::JSON.parse(report)
        report = parsed if parsed.is_a?(Hash)
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
        raise "Failed to parse JSON response from Copilot Usage Service: #{e.message}"
      end
    end

    if report.is_a?(Hash) && report["download_links"].is_a?(Array)
      report["download_links"].map do |url|
        {
          "name" => display_name_for(url),
          "url" => url
        }
      end
    else
      []
    end
  end

  # Derives a display filename from a SAS download URL. The URL's path looks
  # like `/<container>/<path>/<blob name>`, so the basename gives us the real blob
  # filename.
  sig { params(url: String).returns(String) }
  def display_name_for(url)
    File.basename(URI.parse(url).path.to_s)
  end
end
