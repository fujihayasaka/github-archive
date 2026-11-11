# typed: true
# frozen_string_literal: true

class GitHubModels::RepositoryPromptComparisonsController < AbstractRepositoryController
  include Repos::TreePayloadHelper
  include GitHubModels::RepositoryPromptsDependency

  before_action :github_models_required
  before_action :require_feature
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
    ApplicationRecord::Billing,
    optional: true

  layout "repository"

  def self.react_bundle_name
    "github-models-repo"
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
end
