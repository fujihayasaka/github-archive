# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryModelsController < AbstractRepositoryController
  before_action :require_feature
  before_action :github_models_required

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    optional: true

  layout "repository"

  def self.react_bundle_name
    "github-models-repo"
  end

  def index
    render_react_app(
      title: "Models · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models },
      app_payload_generator: -> {
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          )
        }
      }
    )
  end

  private

  def require_feature
    render_404 unless user_feature_enabled?(:github_models_repo_tab)
  end
end
