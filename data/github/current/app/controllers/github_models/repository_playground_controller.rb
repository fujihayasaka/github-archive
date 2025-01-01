# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryPlaygroundController < AbstractRepositoryController
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
  before_action :login_required
  before_action :writable_repository_required
  before_action :require_can_edit_repository
  before_action :add_models_repo_client_side_feature_flags

  # For calling the Azure AI Playground in the browser
  CSP_EXCEPTIONS = {
    connect_src: [
      GitHub.azure_ai_playground_url,
      GitHub.models_gateway_url,
      "*.search.windows.net",
      "*.inference.ai.azure.com",
    ],
    img_src: [
      SecureHeaders::PolicyManagement::DATA_PROTOCOL,
      "*.blob.core.windows.net",
    ],
  }.freeze
  before_action :add_csp_exceptions

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::GitHubModels,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesPushes

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    optional: true

  layout "repository"

  def self.react_bundle_name
    "github-models-repo"
  end

  def index
    first_available_model = available_models.first

    unless first_available_model
      return render_react_app(
        title: "Playground · #{current_repository.name_with_display_owner}",
        page_data: { selected_link: :repo_models_playground },
        app_payload_generator: -> {
          {
            repository: Repos::ReactPayload.current_repository_payload(
              current_repository,
              current_user_can_push: current_user_can_push?
            ),
            canEdit: can_edit?,
            paidUsageBannerDismissed: user_dismissed_paid_notice?,
            isMarketplaceEnabled: GitHub.marketplace_enabled?,
            current_user: {
              login: current_user&.display_login,
              name: current_user&.name,
              avatarUrl: current_user&.primary_avatar_url(80),
              path: user_path(current_user)
            },
            payload: app_payload
          }
        }
      )
    end

    registry, model = first_available_model.values_at(:registry, :name)

    redirect_to models_playground_path(registry: registry, model: model)
  end

  def show
    model = models_repo.model(
      user: models_user,
      registry: params[:registry] || ModelsByok::CustomModel::REGISTRY,
      name: params[:model],
      key: params[:key]
    )
    return render_404 unless model

    payload = GitHubModels::Payloads::Show.new(
      models_user: models_user,
      miniplayground_icebreaker: nil,
      model: models_user.model_hash(model),
      model_input_schema: model.to_schema,
      params: params,
      prompt_extraction_code_snippet: nil,
      improved_prompt_model: improved_prompt_model_if_allowed,
      prompt_extraction_model: nil,
      org: current_repository.organization,
      repository: models_repo,
    ).call

    render_react_app(
      title: "Playground · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models_playground },
      app_payload_generator: -> {
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          canEdit: can_edit?,
          enabled_features: {},
          paidUsageBannerDismissed: user_dismissed_paid_notice?,
          isMarketplaceEnabled: GitHub.marketplace_enabled?,
          current_user: {
            login: current_user&.display_login,
            name: current_user&.name,
            avatarUrl: current_user&.primary_avatar_url(80),
            path: user_path(current_user)
          },
          payload: app_payload,
          businessSlug: business_slug,
          rateLimitLink: doc_urls[:rateLimit],
        }
      },
      payload: payload,
    )
  end

  private

  def require_feature
    super
  end

  sig { returns T::Array[DefaultAndCustomModels::Types::RepoModel] }
  memoize def available_models
    models_repo.models(user: models_user).map(&:to_repository_model)
  end

  def improved_prompt_model_if_allowed
    gpt_4o_available = available_models.find { |m| m[:registry] == "azure-openai" && m[:name] == "gpt-4o" }
    return nil unless gpt_4o_available

    get_improved_prompt_model
  end

  def app_payload
    GitHubModels::Payloads::Prompt.new(
      models_user: models_user,
      improved_sys_prompt_model: nil,
      prompt: "",
      prompt_path: "",
      prompt_ref: current_commit&.oid,
      repository: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      inference_url: models_user.playground_url(org: current_repository.organization),
      commit_info: get_commit_info(tree_name: tree_name, tree_type: tree_type, commit_sha: commit_sha, create: true),
      can_edit: can_edit?,
      paid_usage_banner_dismissed: user_dismissed_paid_notice?,
      business_slug: business_slug,
      user_settings: GitHubModels::Kv.get_user_repo_settings(current_user&.id, current_repository.id),
      rate_limit_link: doc_urls[:rateLimit],
    ).call
  end
end
