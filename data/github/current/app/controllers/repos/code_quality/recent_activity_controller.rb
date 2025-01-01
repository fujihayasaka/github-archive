# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RecentActivityController < Repos::CodeQuality::BaseRepositoryController
  include CodeQuality::FindingsSerializer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:show]

  before_action :check_code_quality_read

  class ShowPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualityRecentActivityRoute"
    end

    sig do
      params(
        owner: String,
        repo: String,
        default_branch: String,
        file_findings: T::Array[T::Hash[Symbol, T.untyped]],
      ).void
    end
    def initialize(owner, repo, default_branch, file_findings)
      @owner = owner
      @repo = repo
      @default_branch = default_branch
      @file_findings = file_findings
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        owner: @owner,
        repo: @repo,
        defaultBranch: @default_branch,
        fileFindings: @file_findings,
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
    )

    respond_with_react(
      title: "Code quality · Recent activity · #{current_repository.name_with_display_owner}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_sidebar_container",
      page_data: {
        selected_tab: :code_quality_recent_activity
      }
    )
  end
end
