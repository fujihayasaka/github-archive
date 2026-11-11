# frozen_string_literal: true

class DotcomRegistry
  include Memoizable

  HOST     = "github.com"
  TYPE     = "git_source"
  USERNAME = "x-access-token"

  def self.compatible_with?(credentials)
    return false unless credentials.is_a? Hash

    credentials["host"] == HOST && credentials["type"] == TYPE
  end

  def initialize(repo = nil)
    raise ArgumentError if Dependabot.proxima? && repo.blank?

    @repo = repo
  end

  def credentials
    return nil unless Dependabot.enterprise? || Dependabot.proxima?
    return nil if dotcom_access_token.blank?

    {
      "host" => HOST,
      "type" => TYPE,
      "username" => username,
      "password" => dotcom_access_token,
    }
  end

  private

  attr_reader :repo

  def username
    return "proxima-service-identity" if Dependabot.proxima? && repo

    USERNAME
  end

  def dotcom_access_token
    memoize(:dotcom_access_token) do
      if Dependabot.enterprise?
        enterprise_token
      elsif Dependabot.proxima?
        proxima_integration_token
      end
    end
  end

  def proxima_integration_token
    GitHubHelpers.create_proxima_integration_access_token(repo: repo)
  end

  def enterprise_token
    GitHubHelpers.with_connection_failure_retrying do
      client.post("enterprise/tokens").token
    end
  rescue Octokit::NotFound
    Dependabot::Logger.warn(
      msg: "GitHub Connect is not enabled",
      "code.namespace" => "DotcomRegistry",
      **repo.telemetry_attributes,
    )

    nil
  end

  def client
    @client ||=
      GitHubHelpers.octokit_client_for(
        api_endpoint: Dependabot::Application.target_github_internal_api_endpoint,
        bearer_token: GitHubHelpers.integration_token
      )
  end
end
