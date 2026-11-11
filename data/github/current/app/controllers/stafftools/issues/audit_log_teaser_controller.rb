# typed: true
# frozen_string_literal: true

class Stafftools::Issues::AuditLogTeaserController < StafftoolsController
  before_action :ensure_repo_exists
  before_action :ensure_issue_exists

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  def show
    fetch_audit_log_teaser(this_issue_query)

    render \
      partial: "stafftools/audit_log",
      locals: {
        query: @query,
        logs: @logs,
        more_results: @more_results,
      }
  rescue Faraday::TimeoutError
    render plain: "Audit log teaser unavailable (timeout)", status: :service_unavailable
  end

  private

  def this_issue_query
    if GitHub.driftwood_ade_queries_enabled?
      "webevents | where issue_id == #{this_issue.id} or (action startswith 'user_content_edit' and user_content_id == #{this_issue.id} and user_content_type == '#{this_issue.class}')"
    else
      "data.issue_id:#{this_issue.id} OR (data.user_content_id:#{this_issue.id} AND data.user_content_type:#{this_issue.class} AND action:user_content_edit.*)"
    end
  end
end
