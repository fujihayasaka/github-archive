# typed: true
# frozen_string_literal: true

class GitHubModels::PullRequestPromptsController < AbstractRepositoryController
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
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

  def show
    pull = PullRequest.with_number_and_repo(params[:pull_number].to_i, current_repository)
    return render_404 unless pull.present?

    diff = pull.historical_comparison.init_diffs
    if !diff.available? || diff.truncated_for_timeout?
      # For now, we just return a 400 here. The only exposed entry point relies on the diff already existing for
      # the PR to show up, so this should be fine for now.
      return head :bad_request
    end

    # Get diff entry for prompt
    prompt_path = path_string.to_s
    diff_entry = diff[prompt_path]

    # We only support a few operations for now. The only entrypoint to this experience in the UI is only exposed:
    # - if the diff exists, we have a merge commit
    # - a prompt is added or modified, not when it's removed
    # so we exit early for some scenarios which we don't handle well yet.
    return render_404 unless diff_entry.present?
    return head :bad_request if diff_entry.deleted?

    # Fetch prompt data
    unless diff_entry.added?
      base_prompt_content = current_repository.blob(diff_entry.a_sha, diff_entry.a_path).data
    end

    base_prompt = GitHubModels::Payloads::PromptInfo.new(
      path: diff_entry.a_path,
      content: base_prompt_content,
      ref: pull.base_ref_name,
      sha: pull.base_sha,
    )

    head_prompt_content = current_repository.blob(diff_entry.b_sha, diff_entry.b_path).data
    head_prompt = GitHubModels::Payloads::PromptInfo.new(
      path: diff_entry.b_path,
      content: head_prompt_content,
      ref: pull.head_ref_name,
      sha: pull.head_sha,
    )

    # Routes format must be set to false to avoid inferring request format from the file extension.
    # At the same time default file format must be set to `:html` to ensure that rails pages work as expected.
    # According to the docs default format cannot be overridden, therefore we need to set it explicitly based on the
    # Accept header.
    request.format = :json if json_request?

    payload = GitHubModels::Payloads::PromptCompare.new(
      models_user: models_user,
      repository: Repos::ReactPayload.current_repository_payload(
        current_repository,
        current_user_can_push: current_user_can_push?
      ),
      improved_sys_prompt_model: get_improved_prompt_model,
      pull_request_number: pull.number,
      pull_request_title: pull.title,
      base_prompt: base_prompt,
      head_prompt: head_prompt,
      commit_info: get_commit_info(tree_name: pull.head_ref_name, tree_type: "branch", commit_sha: pull.head_sha, create: false),
      inference_url: models_user.playground_url(org: current_repository.organization),
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
          payload: payload,
        }
      },
      page_data: {
        # The review page uses a full-page layout
        hide_footer: true,
        hide_header_content: true,
        title: "#{prompt_path} · #{current_repository.name_with_display_owner}",
      },
      layout: "application",
      disable_ssr: true,
    )
  end
end
