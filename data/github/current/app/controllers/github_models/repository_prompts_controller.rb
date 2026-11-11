# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryPromptsController < AbstractRepositoryController
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
  before_action :login_required, only: [:show]
  before_action :require_can_edit_repository, only: [:new]
  before_action :add_models_repo_client_side_feature_flags

  PER_PAGE = 20

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
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Billing

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    optional: true

  layout "repository_with_container"

  def self.react_bundle_name
    "github-models-repo"
  end

  def index
    prompts = GitHubModels::Prompt.for_repo(current_repository).chronological
      .paginate(page: current_page, per_page: PER_PAGE)
    route_payload = { # Keep in sync with `ModelRepoPromptsRoutePayload` in ui/packages/github-models-repo/types.ts
      prompts: prompts.map(&:to_repo_prompt).as_json,
      page: prompts.current_page,
      totalPages: prompts.total_pages,
    }

    render_react_app(
      title: "Prompts · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models_prompts },
      payload: route_payload,
      app_payload_generator: -> {
        # Keep in sync with `ModelRepoPromptsAppPayload` in ui/packages/github-models-repo/types.ts
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          totalPrompts: prompts.count,
          canEdit: can_edit?,
          restrictedModels: models_user.restricted_models,
          paidUsageBannerDismissed: user_dismissed_paid_notice?,
          current_user: {
            login: current_user&.display_login,
          },
          businessSlug: business_slug,
          rateLimitLink: doc_urls[:rateLimit],
        }
      }
    )
  end

  def show
    return redirect_to repo_models_prompt_new_path unless path_string.present?
    return render_404 unless current_commit

    blob = GitHubModels::Prompt.blob(repo: current_repository, path: path_string, oid: current_commit.oid)
    return render_404 if blob.nil?

    render_model_prompt(ref: current_commit.oid, path: path_string.to_s, content: blob.data)
  end

  def new
    render_model_prompt(ref: current_commit&.oid, path: "", content: "", create: true)
  end
end
