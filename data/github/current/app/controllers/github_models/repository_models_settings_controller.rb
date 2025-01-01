# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryModelsSettingsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :models_enabled_for_repo
  before_action :github_models_required
  before_action :parse_json_params, only: [:create]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create, :destroy]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  # Return all settings for the current repository and user
  def index
    settings = GitHubModels::Kv.get_user_repo_settings(current_user.id, current_repository.id)
    render status: :ok, json: settings.to_json
  end

  def create
    key = params[:key].to_s
    value = params[:value].to_s
    if key.blank? || value.blank?
      return render status: :bad_request, json: { error: "Key and value must be present" }
    end

    GitHubModels::Kv.set_user_repo_settings(current_user.id, current_repository.id, key, value)
    render status: :created, json: { key => value }
  end

  private

  sig { void }
  def models_enabled_for_repo
    render_404 unless models_repo.models_enabled_for_repo?
  end

  sig { returns GitHubModels::Repository }
  memoize def models_repo
    GitHubModels::Repository.new(repository: current_repository)
  end
end
