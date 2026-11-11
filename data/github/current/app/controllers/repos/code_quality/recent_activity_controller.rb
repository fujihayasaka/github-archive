# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RecentActivityController < Repos::CodeQuality::BaseRepositoryController
  include CodeQuality::FindingsSerializer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::RepositoriesPushes,
    only: [:show],
    optional: true

  before_action :check_code_quality_read

  class ShowPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualityAIFindingsRoute"
    end

    sig do
      params(
        owner: String,
        repo: String,
        default_branch: String,
        file_findings: T::Array[T::Hash[Symbol, T.untyped]],
        copilot_swe_agent_enabled: T::Boolean,
        copilot_coding_agent_docs_url: String,
        code_quality_docs_urls: T::Hash[String, String],
        branch_list_cache_key: String,
        has_repo_write_access: T::Boolean,
      ).void
    end
    def initialize(owner, repo, default_branch, file_findings, copilot_swe_agent_enabled, copilot_coding_agent_docs_url, code_quality_docs_urls, branch_list_cache_key, has_repo_write_access)
      @owner = owner
      @repo = repo
      @default_branch = default_branch
      @file_findings = file_findings
      @copilot_swe_agent_enabled = copilot_swe_agent_enabled
      @copilot_coding_agent_docs_url = copilot_coding_agent_docs_url
      @code_quality_docs_urls = code_quality_docs_urls
      @branch_list_cache_key = branch_list_cache_key
      @has_repo_write_access = has_repo_write_access
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        owner: @owner,
        repo: @repo,
        defaultBranch: @default_branch,
        fileFindings: @file_findings,
        copilotSWEAgentEnabled: @copilot_swe_agent_enabled,
        copilotCodingAgentDocsUrl: @copilot_coding_agent_docs_url,
        codeQualityDocsUrls: @code_quality_docs_urls,
        branchListCacheKey: @branch_list_cache_key,
        hasRepoWriteAccess: @has_repo_write_access,
      }
    end
  end

  sig { void }
  def show
    return render_404 unless CodeQuality.recent_activity_enabled?(current_repository)

    response = GitHub::Turboquality.client.get_ai_findings(Turboquality::Proto::GetAiFindingsRequest.new(
      repository_id: current_repository.id,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    highlighted_diff = SyntaxHighlightedDiff.new(current_repository)

    payload = ShowPayload.new(
      current_repository.owner.display_login,
      current_repository.name,
      current_repository.default_branch,
      serialized_ai_file_findings(response.data.ai_file_findings, highlighted_diff),
      current_repository.copilot_swe_agent_enabled?(current_user),
      copilot_coding_agent_docs_url,
      CodeQuality.code_quality_docs_urls,
      helpers.ref_list_cache_key(repository: current_repository),
      current_repository.writable_by?(current_user),
    )

    respond_with_react(
      title: "Code quality · AI findings · #{current_repository.name_with_display_owner}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_sidebar_container",
      page_data: {
        selected_tab: :code_quality_recent_activity
      }
    )
  end

  private

  sig { returns(String) }
  def copilot_coding_agent_docs_url
    DocsUrlConfig.url_for("copilot/managing-access")
  end
end
