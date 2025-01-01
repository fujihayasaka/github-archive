# typed: true
# frozen_string_literal: true

class Settings::Copilot::SweAgentController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include JsonDependency

  allow_verified_fetch only: [:update_repos]

  before_action :login_required
  before_action :redirect_on_no_emu_seat, only: [:index, :update_repos]
  before_action :parse_json_params, only: [:update_repos]

  stylesheet_bundle :suggestions, :copilot
  javascript_bundle :settings
  javascript_bundle :"copilot-swe-agent-repos-picker"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index, :update_repos]

  def index
    selected_repos = case copilot_user.copilot_swe_agent_access
    when Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enabled_repositories_for_owner(copilot_user.user_object).map { |repo| format_selected_repo(repo) }
    else
      []
    end
    render "settings/copilot/swe_agent", locals: {
      mode: copilot_user.copilot_swe_agent_access.serialize,
      selection: selected_repos,
      copilot_user: copilot_user,
      project_display_name: Copilot::SWE_AGENT_DISPLAY_NAME_SHORT,
      mode_changed_callback_path: copilot_swe_agent_update_repos_path,
      selections_changed_callback_path: copilot_swe_agent_update_repos_path,
      access_warning_banner_content: access_warning_banner_content,
    }
  end

  def update_repos # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless request.xhr?
    return head :not_found unless GitHub.copilot_enabled?

    copilot_user.update_copilot_swe_agent_access(params[:mode], false, actor: copilot_user.user_object) if params[:mode].present?
    if copilot_user.copilot_swe_agent_access == Configurable::CopilotSweAgentAccess::State::SELECTED_REPOS
      CopilotSweAgent::RepoEnablement.enable_for_repositories!(repository_ids: params[:selected_repos], owner: copilot_user.user_object, enabled_by: copilot_user.user_object)
    end
    # Unsure if we need anything in the response payload
    head :ok
  end

  private

  def format_selected_repo(repo)
    {
      id: repo.id,
      name: repo.name,
      ownerLogin: repo.owner.display_login,
      visibility: repo.visibility,
    }
  end

  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
  end

  sig { void }
  def redirect_on_no_emu_seat
    if copilot_user.is_enterprise_managed?
      redirect_to "/settings/profile" unless copilot_user.has_enterprise_seat?
    end
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
