# typed: true
# frozen_string_literal: true

class Hovercards::IssuesAndPullRequestsController < ApplicationController
  # Opted out SAML to be handled manually in show action to render a custom SAML SSO interstitial
  include Hovercards::ConditionalAccessMethods
  # For the PULL_REQUESTS_TAG
  include IssuesHelper

  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:show]

  def show
    return render_404 if !this_deleted_issue && !this_issue_or_pr
    return render_404 if target_type_is_issue && !has_issues_enabled?

    return render json: { message: "This issue was deleted" }, status: :gone if this_deleted_issue && repo_readable_by?(current_user)
    return render_404 if !check_access_permissions
    return render_sso if is_private_repo? && !required_external_identity_session_present?

    issue_or_pr = Hovercard::Loader.load_for(
      this_issue_or_pr,
      this_repository,
      current_user,
      cap_filter: cap_filter,
      include_notification_contexts: show_subscription_status,
      comment_id: params[:comment_id].presence&.to_i,
      comment_type: comment_type,
      disable_issues_graph: disable_issues_graph
    )

    render "hovercards/issues_and_pull_requests/show",
      locals: {
        issue_or_pr: issue_or_pr,
        show_subscription_status: show_subscription_status
      },
      layout: false
  end

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if this_issue_or_pr&.pull_request?
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  private

  def repo_readable_by?(user)
    return @repo_readable_by if defined?(@repo_readable_by)
    @repo_readable_by = this_repository.public? || this_repository.readable_by?(user)
  end

  def check_access_permissions
    return false unless repo_readable_by?(current_user)
    return false unless this_issue_or_pr.readable_by?(current_user)
    return false if logged_in? && current_user.blocked_by?(this_issue_or_pr.user)
    return false if this_issue_or_pr.spammy? && (!logged_in? || current_user != this_issue_or_pr.user)

    true
  end

  # used to render in the conditional access enforcement pop-up
  def target_type
    this_issue_or_pr&.pull_request? ? "PullRequest" : "Issue"
  end

  def target_type_is_issue
    target_type == "Issue"
  end

  def render_sso
    render "hovercards/issues_and_pull_requests/sso",
      locals: {
        repository: this_repository,
        return_to_path: return_to_path,
        is_issue: target_type_is_issue
      },
      layout: false
  end

  # only allow relative paths for the return_to option on the SSO link, otherwise link to the
  # user dashboard
  #
  def return_to_path
    return home_path unless params[:current_path]
    parsed = Addressable::URI.parse(params[:current_path])

    if parsed.relative? && parsed.host.nil?
      parsed.userinfo = nil
      parsed.normalize.to_s
    else
      home_path
    end
  end

  def is_private_repo?
    this_repository.private?
  end

  def has_issues_enabled?
    this_repository&.has_issues?
  end

  def this_deleted_issue
    return nil if this_repository.nil?
    return nil unless (number = params[:id].to_i) > 0
    DeletedIssues::Public.by_number(number, repository_id: this_repository.id)
  end

  def this_issue_or_pr
    current_issue_or_pr
  end

  memoize def this_repository
    Repository.nwo(params[:user_id], params[:repository])
  end

  memoize def current_repository
    Repository.nwo(params[:user_id], params[:repository])
  end

  memoize def current_issue_or_pr
    return nil unless this_repository

    current_issue = this_repository.issues.find_by(number: params[:id].to_i)
    return nil unless current_issue
    if current_issue.pull_request?
      current_issue.pull_request
    else
      current_issue
    end
  end

  memoize def comment_type
    case params[:comment_type]
    when IssueOrPullRequestHovercard::REVIEW_COMMENT_TYPE,
         IssueOrPullRequestHovercard::REVIEW_TYPE
      params[:comment_type]
    else
      IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
    end
  end

  def target_for_conditional_access
    @repo ||= Repository.nwo(params[:user_id], params[:repository])
    return :no_target_for_conditional_access unless @repo.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    # security issue: repository.owner does not take into account org-owned private repository forks
    # see https://github.com/github/authorization/issues/1623 for more information
    @repo.owner
  end

  def show_subscription_status
    params[:show_subscription_status] == "true"
  end

  memoize def disable_issues_graph
    GitHub.flipper[:hovercard_issue_pr_disable_issues_graph].enabled? || current_user&.feature_enabled?(:hovercard_issue_pr_disable_issues_graph)
  end
end
