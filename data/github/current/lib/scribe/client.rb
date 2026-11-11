# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-scribe-artifacts"
require "monolith-twirp-scribe-recaps"

class Scribe::Client
  SERVICE_NAME = "scribe_github_client"
  class Error < StandardError; end
  class PermissionDenied < Error; end
  class Unavailable < Error; end
  class Internal < Error; end

  def initialize(http_adapter: self.class.default_http_adapter)
    @http_adapter = http_adapter
    @twirp_client = Scribe::Recaps::V1::RecapsAPIClient.new(http_adapter)
    @artifacts_twirp_client = Scribe::Artifacts::V1::ArtifactsAPIClient.new(http_adapter)
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

    Scribe::Recaps::V1::GetRecapsResponse.decode(response.body)
  end

  def generate_project_recap(user:, project:, view_id:, filter_query: "", prompt_options: nil, timezone: "")
    return empty_response unless user.present? && project.present?
    return empty_response unless GitHub.scribe_enabled?(user: user)

    response = twirp_client.generate_project_recap(
      viewer_id: user.id,
      project_id: project.id,
      view_id:,
      project_number: project.number,
      project_owner: project.owner.display_login,
      project_owner_type: project.owner.class.name.underscore,
      filter_query:,
      prompt_options:,
      timezone:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Recaps::V1::GenerateProjectRecapResponse.decode(response.body)
  end

  def delete_recap(user:, recap_id:)
    return empty_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = twirp_client.delete_recap(
      viewer_id: user.id,
      recap_id:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Recaps::V1::DeleteRecapResponse.decode(response.body)
  end

  def create_artifact(user:, resource_type:, resource_id:, type:, name:, body:, requested_by: nil)
    return empty_artifact_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = artifacts_twirp_client.create_artifact(
      actor_id: user.id,
      requested_by_actor_id: requested_by&.id,
      resource_type:,
      resource_id:,
      type:,
      name:,
      body:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Artifacts::V1::CreateArtifactResponse.decode(response.body)
  end

  def get_artifact(user:, resource_type:, resource_id:, number:)
    return empty_artifact_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = artifacts_twirp_client.get_artifact(
      resource_type:,
      resource_id:,
      number:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Artifacts::V1::GetArtifactResponse.decode(response.body)
  end

  def update_artifact(user:, resource_type:, resource_id:, number:, name:, body:)
    return empty_artifact_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = artifacts_twirp_client.update_artifact(
      resource_type:,
      resource_id:,
      number:,
      name:,
      body:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Artifacts::V1::UpdateArtifactResponse.decode(response.body)
  end

  def destroy_artifact(user:, resource_type:, resource_id:, number:)
    return empty_destroy_artifact_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = artifacts_twirp_client.destroy_artifact(
      resource_type:,
      resource_id:,
      number:,
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Artifacts::V1::DestroyArtifactResponse.decode(response.body)
  end

  def list_artifacts(user:, resource_type:, resource_id:, type: nil)
    return empty_artifacts_response unless user.present? && GitHub.scribe_enabled?(user: user)

    response = artifacts_twirp_client.get_artifacts(
      resource_type:,
      resource_id:,
      type: type || "",
    )

    if response.error
      handle_error(response.error)
    end

    Scribe::Artifacts::V1::GetArtifactsResponse.decode(response.body)
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

  def empty_artifact_response
    { artifact: nil }
  end

  def empty_artifacts_response
    { artifacts: [] }
  end

  def empty_destroy_artifact_response
    { success: false }
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

  attr_reader :http_adapter, :twirp_client, :artifacts_twirp_client
end
