# typed: true
# frozen_string_literal: true

class Api::ImportIssues < Api::App
  include Api::Issues::EnsureIssuesEnabled

  include Api::App::UsersDependency

  before do
    ensure_not_blocked! current_user, current_repo.owner_id
    ensure_issues_enabled!(current_repo)
  end

  # Add a new issue to be imported.
  post "/repositories/:repository_id/import/issues", operation_id: "repos/import-issue" do

    control_access :import_issue,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_payload_size!
    data = receive_with_schema("import-issue", "create")
    validate_required_fields data

    queued_issue = GitHub.issue_importer.push repo: current_repo, current_user: current_user, issue_data: data
    deliver :imported_issue_hash, queued_issue, status: 202, repo: current_repo
  end

  # Get the status of all imported issues.
  #
  # This response is paginated, and accepts a "since" parameter to only
  # inspect migrated issues that have been worked on since a given time.
  # https://github.com/github/octoshift/issues/5199
  get "/repositories/:repository_id/import/issues", operation_id: :deprecated do
    @route_owner = "@github/data-liberation"
    @documentation_url = "#{GitHub.gist_url}/jonmagic/5282384165e0f86ef105#check-status-of-multiple-issues"

    control_access :import_issue,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issues = GitHub.issue_importer.
      get_all(repo: current_repo, current_user: current_user, updated_since: time_param!(:since)).
      includes(:import_errors)
    deliver :imported_issue_hash, issues, status: 200, repo: current_repo
  end

  # Get the status of an individual imported issue.
  # https://github.com/github/octoshift/issues/5199
  get "/repositories/:repository_id/import/issues/:issue_id", operation_id: :deprecated do
    @route_owner = "@github/data-liberation"
    @documentation_url = "#{GitHub.gist_url}/jonmagic/5282384165e0f86ef105#check-status-of-issue-import"

    control_access :import_issue,
      repo: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue = GitHub.issue_importer.get repo: current_repo, current_user: current_user, id: params[:issue_id]
    deliver :imported_issue_hash, issue, status: 200, repo: current_repo
  end

  def validate_required_fields(data)
    errors = []

    if issue_data = data["issue"]
      %w[title body].each do |field|
        if issue_data[field].blank?
          errors.push resource: "Issue", code: "missing_field", field: field
        end
      end
    end
    if comments = data["comments"]
      comments.each_with_index do |comment_data, i|
        if comment_data["body"].blank?
          errors.push resource: "IssueComment", index: i, code: "missing_field", field: "body"
        end
      end
    end

    if errors.any?
      deliver_error! 422,
        errors: errors
    end
  end

  def ensure_payload_size!
    if request.content_length.to_i > GitHub.issue_import_max_json_bytes
      GitHub.dogstats.increment("import.api.queue-issue.blocked.payloads-size")
      deliver_error! 413,
        message: "Payload too big: #{GitHub.issue_import_max_json_bytes} bytes are allowed, #{request.content_length.to_i} bytes were posted."
    end
  end
end
