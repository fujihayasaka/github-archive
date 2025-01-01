# typed: true
# frozen_string_literal: true

class Dashboard::IssuesController < ApplicationController
  include Dashboard::IssuesQueryConcern
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Pages

  depends_on_clusters ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Permissions,
    optional: true

  def index
    return head(406) unless user_dashboard_lists_enabled?

    flow = Issue::ControlFlow.new(
      params:           params,
      pulls_only:       pulls_only?,
      components:       parsed_issues_query,
      current_path:     T.must(request).fullpath,
      current_user:     current_user,
      exclude_archived: true,
    )
    query = flow.query

    self.parsed_issues_query = Search::Queries::IssueQuery.parse(query, current_user)

    result = Issue::SearchResult.search(
      query:        parsed_issues_query,
      current_user: current_user,
      remote_ip:    T.must(request).remote_ip,
      user_session: user_session,
      tags:         query_parsed_search_tags,
      per_page: 12,
      context:      "#{T.must(self.class.name).demodulize.underscore}-#{__method__}-#{pulls_only? ? 'pulls' : 'issues'}",
    )

    render json: { data: pulls_only? ? authorized_pulls(result[:issues]) : authorized_issues(result[:issues]) }
  end

  private

  def resource_for_conditional_access
    # Safe because login_required
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    # Safe because login_required
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def authorized_pulls(issues)
    cap_filter.authorized_resources(issues)
      .select(&:pull_request?)
      .map do |issue|
        DashboardPullRequest.new(issue.pull_request, viewer: current_user).to_h
      end
  end

  def authorized_issues(issues)
    cap_filter.authorized_resources(issues)
      .filter_map do |issue|
        DashboardIssue.new(issue).to_h
      end
  end
end
