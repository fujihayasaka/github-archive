# typed: true
# frozen_string_literal: true

class IssuesPartialsController < AbstractRepositoryController
  include ShowPartial
  include TimelineHelper

  layout false

  before_action :find_issue

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
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
    ApplicationRecord::Spokes,
    optional: false, only: [:load_more]

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
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:body]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:transfer_form_possible_repositories]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:transfer_form]

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
    ApplicationRecord::Spokes,
    optional: false, only: [:unread_timeline]

  def body # rubocop:todo GitHub/UseRestfulActions
    issue_node = Issue::Loader::CommentLoader.issue_node(@issue, current_repository, current_user, cap_filter: cap_filter)

    respond_to do |format|
      format.html do
        render partial: "issues/body", object: @issue, locals: { issue: issue_node }
      end
    end
  end

  def load_more # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless valid_cursors?(params[:before_cursor], params[:after_cursor])

    pagination_params = {
      per_page: params[:timeline_per_page] || DEFAULT_PAGE_SIZE,
      before_cursor: params[:before_cursor],
      after_cursor: params[:after_cursor],
      first: params[:first],
      timeline_since: params[:since],
    }

    timeline_owner = Issue::ShowLoader.issue_node(
      @issue,
      current_repository,
      current_user,
      cap_filter: cap_filter,
      pagination_params: pagination_params
    )

    render Issues::PagedTimelineComponent.new(timeline_owner: timeline_owner), layout: false
  end

  def unread_timeline # rubocop:todo GitHub/UseRestfulActions
    # If the timeline_since parameter is present but invalid, return a bad request.
    # Determining if the parameter is invalid is non-trivial since the comparison downstream
    # ends up being between an ActiveSupport::TimeWithZone and the input string. The
    # ActiveSupport::TimeWithZone class implements the <=> operator (all that is required to do comparisons)
    # by converting itself to `utc` which returns a Time class. The Time class implements the <=> operator
    # by checking the counterpart argument i.e. the left hand side to be valid in C code, which I can't
    # find any good reference on how to invoke from Ruby. See:
    # https://github.com/ruby/ruby/blob/129663c4a8e1522a862a26b99e997854186bafac/time.c#L1765.
    return head :bad_request if params[:since].present? && Time.now.utc.<=>(params[:since]).nil?

    pagination_params = { timeline_since: params[:since] }

    timeline_owner = Issue::ShowLoader.issue_node(@issue, current_repository, current_user, pagination_params: pagination_params, cap_filter: cap_filter)

    respond_to do |format|
      format.html do
        render partial: "issues/unread_timeline", object: @issue, locals: { issue: timeline_owner }
      end
    end
  end

  def transfer_form_possible_repositories # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Issues::IssueTransferPossibleReposComponent.new(issue: @issue, viewer: current_user), layout: false
      end

      format.html_fragment do
        render Issues::IssueTransferPossibleReposComponent.new(issue: @issue, viewer: current_user, filter: params[:query]), layout: false
      end
    end
  end

  def transfer_form # rubocop:todo GitHub/UseRestfulActions
    form_path = issues_transfer_form_possible_repositories_partial_path(id: @issue.number, issue: @issue.number)

    respond_to do |format|
      format.html do
        render Issues::IssueTransferFormComponent.new(issue: @issue, form_path: form_path), layout: false
      end
    end
  end

  # Override AbstractRepositoryController#defer_commit_badges? to
  # opt-in to deferred loading of commit signature badges.
  def defer_commit_badges? # rubocop:todo GitHub/UseRestfulActions
    true
  end

  # Override AbstractRepositoryController#defer_status_check_rollups? to
  # opt-in to deferred loading of status check rollups
  def defer_status_check_rollups? # rubocop:todo GitHub/UseRestfulActions
    true
  end

  private

  def find_issue
    @issue = Issue.find_by(repository_id: current_repository.id, number: params[:id].to_i)
    return head :not_found unless @issue
  end
end
