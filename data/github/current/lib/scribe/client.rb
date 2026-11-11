# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-scribe-scribe"

class Scribe::Client
  SERVICE_NAME = "scribe_github_client"
  class Error < StandardError; end
  class PermissionDenied < Error; end
  class Unavailable < Error; end
  class Internal < Error; end

  def initialize(http_adapter: self.class.default_http_adapter)
    @http_adapter = http_adapter
    @twirp_client = Scribe::V1::ScribeServiceAPIClient.new(http_adapter)
  end

  def get_recaps(user:, project_id:, view_id:)
    return empty_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = twirp_client.get_recaps(
      viewer_id: user.id,
      project_id:,
      view_id:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::V1::GetRecapsResponse.decode(response.body)
  end

  def generate_project_recap(user:, project:, view_id:)
    return empty_response unless user.present? && project.present?
    return empty_response unless GitHub.scribe_enabled?(user: user)

    response = twirp_client.generate_project_recap(
      viewer_id: user.id,
      project_id: project.id,
      view_id:,
      project_number: project.number,
      project_owner: project.owner.display_login,
      project_owner_type: project.owner.class.name.underscore,
      filter_query: "",
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::V1::GenerateProjectRecapResponse.decode(response.body)
  end

  def self.default_http_adapter
    GitHub::FaradayClient::Internal.new(url: GitHub.scribe_twirp_url) do |c|
      c.headers[:user_agent] = "github-#{GitHub.role}"
      c.options[:timeout] = 10
      c.request(:retry, max: 2)
      c.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.scribe_hmac_key
      c.use GitHub::FaradayMiddleware::RequestID
      c.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      c.adapter(:typhoeus)
    end
  end

  private

  def empty_response
    { recaps: [] }
  end

  def handle_error(error)
    case error.code
    when :permission_denied
      raise PermissionDenied, error.msg
    when :unavailable
      raise Unavailable, error.msg
    when :internal
      raise Internal, error.msg
    else
      raise Error, error.msg
    end
  end

  attr_reader :http_adapter, :twirp_client
end
