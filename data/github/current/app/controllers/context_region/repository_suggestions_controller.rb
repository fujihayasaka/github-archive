# typed: true
# frozen_string_literal: true

class ContextRegion::RepositorySuggestionsController < ApplicationController
  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Profiles,
    ApplicationRecord::Repositories

  before_action :login_required
  before_action :require_features_enabled

  INITIAL_RESULT_LIMIT = 8
  SEARCH_RESULT_LIMIT = 25

  def index
    unless owner
      return respond_to do |format|
        format.json do
          render json: { repositories: [] }, status: :not_found
        end
      end
    end

    repositories_payload = find_repositories.map do |repo|
      {
        id: repo.id,
        name: repo.name,
        owner: owner.display_login,
        nameWithOwner: "#{owner.display_login}/#{repo.name}",
        visibility: repo.visibility,
      }
    end

    respond_to do |format|
      format.json do
        render json: { repositories: repositories_payload }
      end
    end
  end

  private

  def find_repositories
    search_query = if has_query?
      "owner:#{params[:owner]} #{params[:query]}"
    else
      "owner:#{params[:owner]}"
    end

    results = ::Search::Repositories.search_repos(
      current_user,
      search_query,
      1,
      per_page: result_limit,
      sort_order: "relevance",
      user_session: user_session,
      cap_filter: cap_filter,
      allow_finder_filters: true,
      experiment_unbounded: FeatureFlag.vexi.enabled?(:repos_finder_unbounded, current_user, default: false)
    )

    results[:repos]
  end

  def require_features_enabled
    global_nav_react_enabled = FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
    repo_picker_experiment_enabled = FeatureFlag.vexi.enabled?(:global_nav_repo_picker_experiment, current_user, default: false)

    render_404 unless global_nav_react_enabled && repo_picker_experiment_enabled
  end

  memoize def owner
    User.find_by_login(params[:owner])
  end

  def has_query?
    params[:query].present?
  end

  def result_limit
    has_query? ? SEARCH_RESULT_LIMIT : INITIAL_RESULT_LIMIT
  end

  def target_for_conditional_access
    owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
