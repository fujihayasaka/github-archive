# typed: strict
# frozen_string_literal: true

class Orgs::CopilotSettings::SweAgentController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency

  allow_verified_fetch only: [:update_repos]

  before_action :login_required
  before_action :dotcom_required
  before_action :org_admins_only
  before_action :parse_json_params, only: [:update_repos]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-for-business"
  end

  sig { void }
  def index
    selected_repos = case current_organization.copilot_swe_agent_access
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enabled_repositories_for_owner(current_organization).map { |repo| format_selected_repo(repo) }
    else
      []
    end
    render_react_app(
      payload: {
        project_display_name: Copilot::SWE_AGENT_DISPLAY_NAME_SHORT,
        selection: selected_repos,
        org_login: current_organization.display_login,
        mode: current_organization.copilot_swe_agent_access.serialize,
        mode_changed_callback_path: settings_org_copilot_swe_agent_update_repos_path,
        selections_changed_callback_path: settings_org_copilot_swe_agent_update_repos_path,
        access_warning_banner_content: access_warning_banner_content,
      },
      title: Copilot::COPILOT_SWE_AGENT,
      layout: "layouts/settings/copilot_org_react",
      disable_ssr: true,
      page_data: { selected_link: :organization_copilot_settings_swe_agent }
    )
  end

  sig { void }
  def update_repos # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    current_organization.update_copilot_swe_agent_access(params[:mode], false, actor: current_user) if params[:mode].present?
    if current_organization.copilot_swe_agent_access == Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enable_for_repositories!(repository_ids: params[:selected_repos], owner: current_organization, enabled_by: current_user)
    end
    # Unsure if we need anything in the response payload
    head :ok
  end


  private

  sig { params(repo: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def format_selected_repo(repo)
    {
      id: repo.id,
      name: repo.name,
      ownerLogin: repo.owner.display_login,
      visibility: repo.visibility,
    }
  end

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { returns(T.nilable(String)) }
  def access_warning_banner_content
    public_user = Copilot::Public::User.new(current_user)

    if !public_user.has_copilot_access? || !public_user.has_premium_access?
      return "You can enable Copilot coding agent for other users, but you won't be able to assign tasks to Copilot because you don't have a Copilot Pro+ or Copilot Enterprise license."
    elsif !public_user.swe_agent_enabled?
      return "You can enable Copilot coding agent for other users, but you won't be able to assign tasks to Copilot because the Copilot coding agent policy has been disabled by an administrator."
    end

    nil
  end
end
