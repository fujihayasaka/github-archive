# typed: true
# frozen_string_literal: true

class Businesses::AgentSourceRepoSuggestionsController < Businesses::BusinessController
  MAX_AGENT_SOURCE_REPO_SUGGESTIONS = 100
  MAX_ORGS_FOR_AGENT_SOURCE_REPO_SUGGESTIONS = 500

  before_action :this_business_required
  before_action :authorize!

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  def index
    query = params[:q].to_s.strip
    owner_query, repo_query = parse_agent_source_repo_query(query)

    repos = if owner_query.present?
      owner = User.find_by_login(owner_query)
      if owner
        scoped = Repositories::Public.active_owned_by(owner.id)
        scoped = scoped.where("name LIKE ?", "%#{Repository.sanitize_sql_like(repo_query)}%") if repo_query.present?
        scoped
      else
        Repository.none
      end
    else
      org_ids = this_business.organizations
        .where("login LIKE ?", "%#{Organization.sanitize_sql_like(query)}%")
        .limit(MAX_ORGS_FOR_AGENT_SOURCE_REPO_SUGGESTIONS)
        .pluck(:id)

      scoped = Repository.where(owner_id: org_ids).active
      scoped = scoped.where("name LIKE ?", "%#{Repository.sanitize_sql_like(query)}%") if query.present?
      scoped
    end

    repos = repos.public_scope.order(:name).limit(MAX_AGENT_SOURCE_REPO_SUGGESTIONS)

    respond_to do |format|
      format.html_fragment do
        render partial: "integrations/settings/agent_source_repo_suggestions", formats: :html, locals: {
          repos: repos,
          selected_repository_id: params[:selected_repository_id].to_i,
        }
      end
    end
  end

  private

  def current_integration
    this_business.integrations.not_marked_for_deletion.find_by!(slug: params[:id])
  end

  def this_business_required
    render_404 if this_business.nil?
  end

  def authorize!
    if params[:id]
      render_404 unless Apps::ManagementHelper.can_edit?(app: current_integration, actor: current_user)
    else
      render_404 unless Apps::ManagementHelper.can_create_apps?(on: this_business, actor: current_user)
    end
  end

  def parse_agent_source_repo_query(query)
    return [nil, nil] unless query.to_s.include?("/")
    owner_query, repo_query = query.split("/", 2)
    [owner_query.to_s.strip, repo_query.to_s.strip]
  end
end
