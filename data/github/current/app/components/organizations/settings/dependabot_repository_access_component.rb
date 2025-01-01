# typed: true
# frozen_string_literal: true

class Organizations::Settings::DependabotRepositoryAccessComponent < ApplicationComponent

  def initialize(organization:, page_param: 1)
    @organization = organization
    @page_param = page_param
  end

  def render?
    return false unless repo_access_available?
    repo_access_response_viewable?
  end

  def repo_access_available?
    return false unless @organization.dependabot_repository_access_enabled_for?(current_user)
    @organization.dependabot_installed?
  end

  def repo_access_response_viewable?
    repo_access&.access_editable || repo_access_service_unavailable?
  end

  def repo_access_service_unavailable?
    @repo_access_service_unavailable
  end

  def repo_access
    return @repo_access if defined?(@repo_access)

    @repo_access = Dependabot::Twirp.repository_access_service_client.get_repository_access(owner_github_id: @organization.id)
  rescue Dependabot::Twirp::BaseError, Faraday::ConnectionFailed
    @repo_access_service_unavailable = true
    @repo_access = nil
  end
end
