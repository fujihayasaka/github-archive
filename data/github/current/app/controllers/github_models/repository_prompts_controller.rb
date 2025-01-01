# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryPromptsController < AbstractRepositoryController
  include Marketplace::Models::RenderDependency

  before_action :require_feature
  before_action :github_models_required
  before_action :login_required, only: [:show, :compare]

  # For calling GitHub Models backend in the browser
  CSP_EXCEPTIONS = {
    connect_src: [GitHub.azure_ai_playground_url, GitHub.models_gateway_url, "*.search.windows.net", "*.inference.ai.azure.com"],
    img_src: [SecureHeaders::PolicyManagement::DATA_PROTOCOL],
    media_src: [GitHub.asset_host_url],
  }.freeze
  before_action :add_csp_exceptions

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
      title: "Prompts · #{current_repository.name_with_display_owner}",
      page_data: { selected_link: :repo_models_prompts },
      app_payload_generator: -> {
        {
          repository: Repos::ReactPayload.current_repository_payload(
            current_repository,
            current_user_can_push: current_user_can_push?
          ),
          canEdit: can_edit?
        }
      }
    )
  end

  def show
    prompt_content = current_repository.blob(current_commit.oid, path_string)
    return render_404 if prompt_content.nil?

    render_model_prompt(ref: current_commit.oid, path: path_string.to_s, content: prompt_content.data)
  end

  def new
    render_model_prompt(ref: current_commit.oid, path: "", content: "")
  end

  def compare # rubocop:disable GitHub/UseRestfulActions
    prompt_content = current_repository.blob(current_commit.oid, path_string).data

    # If we are comparing, fetch the other prompt from the other ref
    head = params[:compare]
    if head.present?
      head_ref = current_repository.refs.find(head)
      head_prompt_content = current_repository.blob(head_ref.sha, path_string).data
    end

    render_model_prompt(ref: current_commit.oid, path: path_string.to_s, content: prompt_content, head_prompt_content: head_prompt_content)
  end

  private

  def require_feature
    render_404 unless user_feature_enabled?(:github_models_repo_tab)
  end

  # Can the current user edit or create prompts within the repository
  def can_edit?
    return false if current_repository.archived? || current_repository.locked_on_migration?
    return false unless logged_in?
    return false if T.must(current_user).must_verify_email?
    current_user_can_push?
  end

  def render_model_prompt(ref:, path:, content:, head_prompt_content: nil)
    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    payload = GitHubModels::Payloads::Prompt.new(
      current_user:,
      improved_sys_prompt_model: get_improved_prompt_model,
      prompt: content,
      prompt_path: path,
      prompt_ref: ref,
      repository: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
    ).call

    render_react_app(
      app_payload_generator: -> {
        {
          current_user: {
            login: current_user&.display_login,
            name: current_user&.name,
            avatarUrl: current_user&.primary_avatar_url(80),
            path: user_path(current_user)
          },
          payload: payload, # We want to re-use this for different pages which don't have route specific data
        }
      },

      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
        title: "#{path} · #{current_repository.name_with_display_owner}",
        stafftools: stafftools_models_path,
        selected_link: :repo_models,
      },
    )
  end
end
