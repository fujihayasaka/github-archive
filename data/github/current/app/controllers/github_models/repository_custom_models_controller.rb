# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryCustomModelsController < AbstractRepositoryController
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
  before_action :login_required_redirect_for_public_repo
  before_action :add_models_repo_client_side_feature_flags

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    optional: true

  def show
    if request.format.json?
      custom_model = models_repo.custom_model(
        user: models_user,
        name: params[:model],
        key: params[:key]
      )
      return render_404 unless custom_model

      return render json: {
        catalogData: custom_model.to_repository_model,
        modelInputSchema: custom_model.to_schema,
        gettingStarted: {}
      }
    end

    head :not_acceptable
  end

  private

  def require_feature
    render_404 unless models_repo.models_enabled_for_repo?
  end

  # Can the current user edit or create prompts within the repository
  def can_edit?
    return false if current_repository.archived? || current_repository.locked_on_migration?
    return false unless logged_in?
    return false if T.must(current_user).must_verify_email?
    current_user_can_push?
  end
end
