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

  def react_repo_access_props
    props = {
      allowedRepositoryPickerScope: {
        type: "organization",
        slug: @organization.display_login,
        visibility: %w(internal private)
      },
      allowedRepositories: allowed_picker_repos,
      setAllowedRepositoriesUrl: settings_org_security_analysis_dependabot_set_allowed_repositories_path(@organization),
    }

    if render_default_repo_access_selection?
      props.merge!(
        accessLevel: @organization.dependabot_default_repository_access,
        setRepositoryAccessUrl: settings_org_security_analysis_dependabot_set_default_repository_access_path(@organization),
      )
    end

    props
  end

  def render_default_repo_access_selection?
    @organization.advanced_security_purchased?
  end

  def allowed_picker_repos
    repo_ids = Array(@repo_access.repository_github_ids)
    Repositories::Public.filter_repo_ids_to_org(organization_id: @organization.id, repo_ids:)
      .find_each
      .map { |repo| repo_to_picker_repo(repo) }
      .sort_by { |r| r[:name] }
  end

  def repo_to_picker_repo(repo)
    {
      id: repo.id,
      node_id: repo.global_relay_id,
      name: repo.name,
      owner_login: @organization.display_login,
      visibility: repo.visibility,
    }
  end

  def internal_repositories_enabled?
    @organization.members_can_create_internal_repositories?
  end
end
