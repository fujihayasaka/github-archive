# typed: true
# frozen_string_literal: true

class Settings::AgentSourceRepoSuggestionsController < ApplicationController
  before_action :login_required
  before_action :sudo_filter

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  MAX_AGENT_SOURCE_REPO_SUGGESTIONS = 100

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
      scoped = current_user.repositories
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

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def parse_agent_source_repo_query(query)
    return [nil, nil] unless query.to_s.include?("/")
    owner_query, repo_query = query.split("/", 2)
    [owner_query.to_s.strip, repo_query.to_s.strip]
  end
end
