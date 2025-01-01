# typed: true
# frozen_string_literal: true

class Hovercards::IssueLinksController < ApplicationController
  before_action :require_xhr, only: [:tracked_in, :tracking]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    optional: false, only: [:tracked_in, :tracking]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:tracked_in, :tracking], optional: true

  def tracked_in # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_repository&.has_issues?
    return render_404 unless this_issue.present?

    render "hovercards/issue_links/tracked_in",
    locals: {
      normalized_tracking_issues: this_issue.normalized_tracking_issues(
        viewer: current_user,
        cap_filter: cap_filter,
      ),
      this_repository: this_repository
    },
    layout: false
  end

  def tracking # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_repository&.has_issues?
    return render_404 unless repository_readable_by_user?(this_repository)
    return render_404 unless this_issue.present?
    return render_404 unless issue_accessible_by_user?(this_issue)

    tracked_by_title = nil
    tracked_issue = Issue.find_by(id: params[:tracked_id])

    if tracked_issue && issue_accessible_by_user?(tracked_issue) && (T.must(tracked_issue.repository).id == this_repository.id || repository_readable_by_user?(tracked_issue.repository))
      tracked_by_title = tracked_issue.parent_issues.find do |parent_issue|
        parent_issue.issue_id == this_issue.id
      end&.tracked_by_title
    end

    this_issue_or_pr = this_issue.pull_request? ? this_issue.pull_request : this_issue

    issue_or_pr = Hovercard::Loader.load_for(
      this_issue_or_pr,
      this_repository,
      current_user,
      cap_filter: cap_filter,
      include_notification_contexts: false,
    )

    render "hovercards/issue_links/tracking",
      locals: {
        issue_or_pr: issue_or_pr,
        tracked_by_title: tracked_by_title,
        tracked_issue: tracked_issue,
      },
      layout: false
  end

  private

  def issue_accessible_by_user?(issue)
    return false unless issue.readable_by?(current_user)
    return false if logged_in? && current_user.blocked_by?(issue.user)
    return false if issue.spammy? && (!logged_in? || current_user != issue.user)
    true
  end

  def repository_readable_by_user?(repository)
    repository.present? && (repository.public? || repository.readable_by?(current_user))
  end

  def target_for_conditional_access
    resource = resource_for_conditional_access
    return :no_target_for_conditional_access if resource == :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    resource.target_for_conditional_access
  end

  def resource_for_conditional_access
    # security issue: repository.owner does not take into account org-owned private repository forks
    # see https://github.com/github/authorization/issues/1623 for more information
    return :no_resource_for_conditional_access unless this_repository # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    this_repository
  end

  # As a quality-of-life improvement, we don't require
  # a SAML session when viewing public repositories.
  def require_active_external_identity_session?
    return this_repository.private? if this_repository.present?
    true
  end

  memoize def this_issue
    issue = this_repository&.issues&.find_by_number(params[:id])
    if issue&.readable_by? current_user
      issue
    else
      nil
    end
  end

  memoize def this_repository
    this_user&.repositories&.find_by_name(params[:repository])
  end

  memoize def this_user
    User.find_by_login(params[:user_id]) if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
  end
end
