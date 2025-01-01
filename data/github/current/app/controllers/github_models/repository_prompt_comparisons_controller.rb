# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryPromptComparisonsController < AbstractRepositoryController
  include Repos::TreePayloadHelper
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
  before_action :require_comparisons_feature, only: [:index]
  before_action :login_required
  before_action :add_models_repo_client_side_feature_flags
  before_action :require_can_edit_repository, only: [:show]

  # For calling GitHub Models backend in the browser
  CSP_EXCEPTIONS = {
    connect_src: [GitHub.azure_ai_playground_url, GitHub.models_gateway_url, "*.search.windows.net", "*.inference.ai.azure.com"],
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
    media_src: [GitHub.asset_host_url],
  }.freeze
  before_action :add_csp_exceptions

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::RepositoriesPushes

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
    prompts = GitHubModels::Prompt.for_repo(current_repository).chronological.limit(50)
    route_payload = { # Keep in sync with `ModelRepoPromptsRoutePayload` in ui/packages/github-models-repo/types.ts
      prompts: prompts.map(&:to_repo_prompt).as_json,
      page: 1,
      totalPages: 1,
    }
    render_react_app(
      payload: route_payload,
      title: "Comparisons · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models_prompts },
      app_payload_generator: -> {
        # Keep in sync with `ModelRepoPromptsAppPayload` in ui/packages/github-models-repo/types.ts
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          canEdit: can_edit?,
          totalPrompts: prompts.count,
          enabled_features: {
            github_models_repo_playground: current_repository.feature_enabled_for_repo_or_owner?(:github_models_repo_playground),
            github_models_billing_ui: current_user&.feature_enabled?(:github_models_billing_ui)
          },
          restrictedModels: models_user.restricted_models,
          github_models_repo_comparisons: current_repository.feature_enabled_for_repo_or_owner?(:github_models_repo_comparisons),
          paidUsageBannerDismissed: user_dismissed_paid_notice?,
          current_user: {
            login: current_user&.display_login,
          },
          businessSlug: business_slug,
        }
      }
    )
  end

  def show
    current_commit = self.current_commit

    prompt_content = if current_commit && path_string.present?
      prompt_blob = current_repository.blob(current_commit.oid, path_string)
      return render_404 unless prompt_blob

      prompt_blob.data
    end

    # If we are comparing, fetch the other prompt from the other ref
    head = params[:compare]
    if head.present?
      head_ref = current_repository.refs.find(head)
      return render_404 unless head_ref

      head_prompt_content = if path_string.present?
        current_repository.blob(head_ref.sha, path_string).data
      end
    end

    render_model_prompt(ref: current_commit&.oid, path: path_string.to_s, content: prompt_content,
      head_prompt_content: head_prompt_content)
  end

  private

  def require_comparisons_feature
    render_404 unless current_repository.feature_enabled_for_repo_or_owner?(:github_models_repo_comparisons)
  end
end
