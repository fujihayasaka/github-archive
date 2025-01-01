# typed: true
# frozen_string_literal: true

class Orgs::DependabotRepositoryAccessController < Orgs::Controller
  before_action :manage_security_products_permission_required
  before_action :require_dependabot_repository_access_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:suggestions]

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render(Organizations::Settings::DependabotRepositorySuggestionsComponent.new(
          org: current_organization,
          query: params[:q],
        ), layout: false)
      end
    end
  end

  def show
    render_form_update
  end

  def add_repositories # rubocop:todo GitHub/UseRestfulActions
    node_ids = Array(params[:repository_ids]).to_set
    repository_ids = node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
    Dependabot::RepositoryAccess
      .for(org: current_organization, actor: current_user)
      .append(repository_ids: repository_ids)

    render_form_update
  end

  def remove_repositories # rubocop:todo GitHub/UseRestfulActions
    node_ids = Array(params[:repository_ids]).to_set
    repository_ids = node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i }
    Dependabot::RepositoryAccess
      .for(org: current_organization, actor: current_user)
      .remove(repository_ids: repository_ids)

    render_form_update
  end

  private

  def require_dependabot_repository_access_feature_enabled
    render_404 unless current_organization.dependabot_repository_access_enabled_for?(current_user)
  end

  def render_form_update
    respond_to do |format|
      format.html_fragment do
        render_form_fragment
      end
      format.html do
        if pjax?
          render_form_fragment
        else
          querystring = { dependabot_page: params[:page] }
          ghas_param = AdvancedSecurityEntitiesLinkRenderer::PAGE_PARAM
          querystring[ghas_param] = params[ghas_param] if params.include? ghas_param
          redirect_to settings_org_security_analysis_path(anchor: "dependabot-repository-access", **querystring)
        end
      end
    end
  end

  def render_form_fragment
    repo_access = Dependabot::Twirp.repository_access_service_client.get_repository_access(owner_github_id: current_organization.id)

    render Organizations::Settings::DependabotRepositoryAccessFormComponent.new(
      organization: current_organization,
      selected_repo_ids: repo_access.repository_github_ids,
      page_param: params[:page],
    )
  end
end
