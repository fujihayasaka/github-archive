# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::PullRequestsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    only: [:pull_request, :commit]

  # Due to scheduled workfows and other automation, there can be a large number of check suites for a single commit so limit how much we fetch from the database
  MAX_CHECK_SUITES_PER_SHA_LIMIT = 5000


  def index
    return render_404 unless GitHub.actions_enabled?
    return render_404 unless current_user.feature_enabled?(:actions_stafftools_pr_page)

    issues = current_repository.issues.order("id DESC").paginate \
      page: params[:page] || 1,
      per_page: 25

    render "stafftools/repositories/actions/pull_requests", locals: {
      repository: current_repository,
      issues: issues,
    }
  end

  def pull_request # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?
    return render_404 unless current_user.feature_enabled?(:actions_stafftools_pr_page)

    pull_request_id = params.require(:pull_request_id)

    pull_request = current_repository.pull_requests.find_by(id: pull_request_id)

    commits = pull_request.changed_commits

    subquery = "refs/heads/#{pull_request.head_ref}"
    push_log_path = "?ref=#{ERB::Util.url_encode(subquery)}"


    render "stafftools/repositories/actions/pull_request", locals: {
      repository: current_repository,
      pull_request: pull_request,
      commits: commits,
      push_log_path: push_log_path
    }
  end

  def commit # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?
    return render_404 unless current_user.feature_enabled?(:actions_stafftools_pr_page)

    pull_request_id = params.require(:pull_request_id)
    sha = params.require(:sha)

    pull_request = current_repository.pull_requests.find_by(id: pull_request_id)
    commit = pull_request.changed_commits.find { |c| c.oid == sha }
    return render_404 if commit.nil?

    most_recent_check_suites = CheckSuite.most_recent_check_suites_for_sha(current_repository.id, commit.oid, MAX_CHECK_SUITES_PER_SHA_LIMIT)

    # Filter check suites into two arrays - one for actions and one for others
    actions_check_suites = most_recent_check_suites.select(&:actions_app?)
    third_party_check_suites = most_recent_check_suites - actions_check_suites

    ActiveRecord::Associations::Preloader.new(
            records: actions_check_suites,
            associations: [:workflow_run],
    ).call

    render "stafftools/repositories/actions/commit", locals: {
      repository: current_repository,
      pull_request: pull_request,
      commit: commit,
      actions_check_suites: actions_check_suites,
      third_party_check_suites: third_party_check_suites
    }
  end
end
