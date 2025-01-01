# typed: true
# frozen_string_literal: true

# Public: Used to fetch issues and pull requests a user has somehow interacted with since
# the specified time.
class Issue::RecentInteractions
  EVENT_ACTIONS = %w[reopened deployed assigned referenced].freeze

  COMMENT_INTERACTION = "commented"
  RECEIVED_COMMENT_INTERACTION = "received_comment"
  COMMENT_EDITED_INTERACTION = "comment_edited"
  RECEIVED_COMMENT_EDITED_INTERACTION = "received_comment_edited"
  OPENED_INTERACTION = "authored"
  ASSIGNED_INTERACTION = "assigned"
  REVIEW_REQUESTED_INTERACTION = "review_requested"
  REVIEW_RECEIVED_INTERACTION = "review_received"
  REVIEW_COMMENTED_INTERACTION = "pull_request_review_commented"

  # Public: Construct a new instance of Issue::RecentInteractions.
  #
  #                      user - a User instance
  #                     since - a DateTime in the past
  #                     types - a list of what kinds of records should be returned; valid values:
  #                             :issue, :pull_request
  #           organization_id - optional Integer database ID for an Organization, if activity should
  #                             be filtered to only include that within the specified org
  #      excluded_account_ids - optional list of Integer database IDs for Users/Organizations whose issues
  #                             and pull requests should be excluded from the results; if
  #                             `organization_id` is given but also included in this list, no
  #                             results will be returned
  def initialize(user, since:, types: nil, organization_id: nil, excluded_account_ids: nil)
    @user = user
    @since = since
    @types = types || [:issue, :pull_request]
    @organization_id = organization_id
    @excluded_account_ids = excluded_account_ids || []
  end

  # Public: Get a list of issues and/or pull requests the user has interacted with.
  #
  # limit - how many results to return
  #
  # Returns an Array of RecentInteraction instances.
  def fetch(limit:)
    return [] if @types.empty?


    sql_results = run_sql_queries
    return [] if sql_results.empty?

    interactions_by_issue_id = get_interactions_by_issue_id(sql_results)
    issues = get_issues(ids: interactions_by_issue_id.keys).
      sort_by { |issue| interactions_by_issue_id[issue.id][:occurred_at] }.
      reverse[0...limit]

    user_by_issue_ids = get_users_by_issue_ids(issues: issues,
                                               interactions_by_issue_id: interactions_by_issue_id)

    issues.map do |issue|
      interactable = issue.pull_request || issue
      data = interactions_by_issue_id[issue.id]

      # exclude recent interactions with spammy commenters
      commenter = user_by_issue_ids[issue.id]
      next if commenter&.spammy?

      RecentInteraction.new(interactable, interaction: data[:interaction],
                            occurred_at: data[:occurred_at], commenter: commenter,
                            comment_id: data[:comment_id])
    end.compact
  end

  private

  def get_issues(ids:)
    issues = Issue.open_issues.includes(issue_query_includes).where(id: ids)

    # Filter to pull requests only unless issues should be included:
    issues = issues.with_pull_requests unless @types.include?(:issue)

    # Filter to issues only unless pull requests should be included:
    issues = issues.without_pull_requests unless @types.include?(:pull_request)

    issues.select { |issue| issue_readable_by_user?(issue) }
  end

  def get_users_by_issue_ids(issues:, interactions_by_issue_id:)
    user_ids_by_issue_id = {}
    issues.map do |issue|
      interactable = issue.pull_request || issue
      interaction = interactions_by_issue_id[issue.id]
      user_ids_by_issue_id[issue.id] = interaction[:user_id]
    end

    user_ids = user_ids_by_issue_id.values.compact.uniq
    users_by_id = User.where(id: user_ids).map { |user| [user.id, user] }.to_h
    users_by_issue_id = {}
    user_ids_by_issue_id.each do |issue_id, user_id|
      users_by_issue_id[issue_id] = users_by_id[user_id]
    end

    users_by_issue_id
  end

  def issue_readable_by_user?(issue)
    repo = issue.repository
    return false unless repo
    return false if repo.user_hidden?
    interactable = issue.pull_request || issue
    return false if interactable.hide_from_user?(@user)
    return false if repo.disabled_at.present?
    repo.readable_by?(@user)
  end

  def issue_query_includes
    includes = [:repository, { repository: :owner }]
    includes << :pull_request if @types.include?(:pull_request)
    includes
  end

  def run_sql_queries
    all_results = []

    issue_event_results = run_sql_query_and_filter_repositories(
      issue_events_sql,
      query_key: "issue-events",
      query_args: issue_event_query_args,
      has_sort_by_id_column: true)

    all_results.concat issue_event_results

    review_request_results = run_sql_query_and_filter_repositories(
      review_requests_sql,
      query_key: "review-requests",
      query_args: review_request_query_args,
      has_sort_by_id_column: true)

    all_results.concat review_request_results

    review_received_results = run_sql_query_and_filter_repositories(reviews_received_sql, query_key: "reviews-received",
                                            query_args: review_received_query_args)

    all_results.concat review_received_results

    review_comment_results = run_sql_query_and_filter_repositories(review_comment_sql, query_key: "added-review-comments",
                                           query_args: review_comment_submitted_query_args)
    all_results.concat review_comment_results

    results_for_created_comments = created_comment_results
    all_results.concat results_for_created_comments

    if (issue_ids = user_open_issue_ids).any?
      rc_results = received_comment_results(issue_ids)
      all_results.concat rc_results
    end

    opened_issue_results = run_sql_query_and_filter_repositories(opened_issues_sql, query_key: "opened-issues",
                                         query_args: opened_issue_query_args)
    all_results.concat opened_issue_results

    assigned_issue_repo_ids = run_sql_query(assigned_issues_repo_ids_sql, query_args: assigned_issue_query_args, query_key: "assigned-issues-repo-ids") if filter_by_organization?

    assigned_issue_results = run_sql_query_and_filter_repositories(
      assigned_issues_sql(repo_ids: assigned_issue_repo_ids),
      query_key: "assigned-issues",
      query_args: assigned_issue_query_args,
      has_sort_by_id_column: true)

    all_results.concat assigned_issue_results

    all_results
  end

  def filter_results_by_repository(results)
    return results.first(20) unless filter_by_organization?
    repo_scope = Repository.where(id: results.map(&:last))
    if @organization_id
      repo_scope = repo_scope.where(owner_id: @organization_id)
    end
    if @excluded_account_ids.any?
      repo_scope = repo_scope.where.not(owner_id: @excluded_account_ids)
    end
    repo_ids = repo_scope.pluck(:id)
    return [] unless repo_ids.any?
    results.lazy.select do |result|
      repo_ids.include? result.last
    end.first(20)
  end

  def drop_repository_id(issue_results)
    return issue_results unless filter_by_organization?

    drop_last_column(issue_results)
  end

  def drop_sort_by_id_column(results)
    drop_last_column(results)
  end

  def drop_last_column(results)
    results.map do |result|
      result[0..-2]
    end
  end

  def created_comment_results(track_time: true)
    results = augment_issue_comments_with_user_content_edits(
      run_sql_query(created_issue_comments_sql,
                    query_key: "created-issue-comments",
                    query_args: created_issue_comment_query_args,
                    track_time: track_time
      ),
      edit_interaction_type: COMMENT_EDITED_INTERACTION,
    )
    results = filter_results_by_repository(results)
    results = drop_repository_id(results)
  end

  def received_comment_results(issue_ids, track_time: true)
    results = augment_issue_comments_with_user_content_edits(
      run_sql_query(
        received_issue_comments_sql,
        query_key: "received-issue-comments",
        query_args: received_issue_comment_query_args(issue_ids),
        track_time: track_time
      ),
      edit_interaction_type: RECEIVED_COMMENT_EDITED_INTERACTION,
    )
    results = filter_results_by_repository(results)
    results = drop_repository_id(results)
  end

  # Simulate the LEFT OUTER JOIN/CASE logic that used to be possible between
  # issue_comments and user_content_edits.  See
  # https://github.com/github/github/blob/8bcb38ccc7fafa679c273100e2a097992f86d88f/app/models/issue/recent_interactions.rb#L250-L260
  # For every issue_comment row, if there is a matching result in
  # user_content_edits, overwrite selected fields with the uce data.
  def augment_issue_comments_with_user_content_edits(issue_comment_rows, edit_interaction_type:)
    issue_comment_ids = issue_comment_rows.map { |row| row[4] }
    edits_by_user_content_id = UserContentEdit.where(user_content_type: "IssueComment", user_content_id: issue_comment_ids)
      .order("edited_at ASC")
      .pluck(:edited_at, :editor_id, :user_content_id)
      .group_by { |edit| edit[2] }
    issue_comment_rows.each_with_object([]) do |row, result|
      if edits = edits_by_user_content_id[row[4]]
        edits.each do |edit|
          edited_row = row.dup
          edited_row[1] = edit_interaction_type # CASE WHEN user_content_edits.editor_id IS NOT NULL THEN :edit_interaction
          edited_row[2] = edit[0]               # CASE WHEN user_content_edits.editor_id IS NOT NULL THEN user_content_edits.edited_at
          edited_row[3] = edit[1]               # CASE WHEN user_content_edits.editor_id IS NOT NULL THEN user_content_edits.editor_id
          result << edited_row
        end
      else
        result << row
      end
    end.slice(0, 20)
  end

  def run_sql_query(sql_query, query_key:, query_args: {}, track_time: true)
    sql = Arel.sql(sql_query, **query_args)

    start = Time.now
    results = Issue.connection.select_rows(sql)
    elapsed_ms = (Time.now - start) * 1_000

    timing_key = if @organization_id
      "recent-activity.#{query_key}.in-org"
    else
      "recent-activity.#{query_key}"
    end
    GitHub.dogstats.timing(timing_key, elapsed_ms) if track_time

    results
  end

  def run_sql_query_and_filter_repositories(sql_query, query_key:, query_args: {}, track_time: true, has_sort_by_id_column: false)
    sql = Arel.sql(sql_query, **query_args)

    start = Time.now
    results = Issue.connection.select_rows(sql)
    elapsed_ms = (Time.now - start) * 1_000

    timing_key = if @organization_id
      "recent-activity.#{query_key}.in-org"
    else
      "recent-activity.#{query_key}"
    end

    GitHub.dogstats.timing(timing_key, elapsed_ms) if track_time

    results = filter_results_by_repository(results)
    results = drop_repository_id(results)

    results = drop_sort_by_id_column(results) if has_sort_by_id_column

    results
  end

  def assigned_issues_repo_ids_sql
    <<-SQL
      SELECT DISTINCT issues.repository_id
      FROM assignments
        INNER JOIN issues ON assignments.issue_id = issues.id
      WHERE assignments.assignee_id = :user_id
        AND (assignments.assignee_type = 'User' OR assignments.assignee_type IS NULL)
        AND assignments.updated_at >= :since
    SQL
  end

  # The user was assigned an issue or pull request
  def assigned_issues_sql(repo_ids: [])
    select_columns = ["assignments.issue_id", ":interaction", "assignments.updated_at", "assignments.id"]
    select_columns << "issues.repository_id" if filter_by_organization?
    select_columns = select_columns.join(", ")
    query = <<-SQL
      SELECT #{select_columns}
      FROM assignments
    SQL

    if filter_by_organization?
      query += <<-SQL
        INNER JOIN issues
        ON assignments.issue_id = issues.id
      SQL
    end

    query += <<-SQL
      WHERE assignments.assignee_id = :user_id
      AND (assignments.assignee_type = 'User' OR assignments.assignee_type IS NULL)
      AND assignments.updated_at >= :since
    SQL

    if filter_by_organization?
      if repo_ids.any?
        query += <<-SQL
          AND issues.repository_id IN (#{repo_ids.join(",")})
        SQL
      else
        query += <<-SQL
          AND 1=0
        SQL
      end
    end

    query += <<-SQL
      ORDER BY assignments.id DESC
    SQL
    query
  end

  def opened_issues_sql
    select_columns  = ["id", ":interaction", "created_at"]
    select_columns << "issues.repository_id" if filter_by_organization?
    select_columns  = select_columns.join(", ")
    query = <<-SQL
      SELECT #{select_columns}
      FROM issues
    SQL

    query += <<-SQL
      WHERE issues.user_id = :user_id
      AND issues.created_at >= :since
      AND issues.state = 'open'
    SQL

    query += <<-SQL
      ORDER BY issues.created_at DESC
    SQL
  end

  # The user opened an issue or pull request that got a comment
  def received_issue_comments_sql
    select_columns = ["issue_comments.issue_id", ":interaction", "issue_comments.updated_at", "issue_comments.user_id", "issue_comments.id"]
    select_columns << "issue_comments.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
      SELECT #{select_columns}
      FROM issue_comments
    SQL

    query += <<-SQL
      WHERE issue_comments.updated_at >= :since
      AND issue_comments.issue_id IN (:issue_ids)
    SQL

    query += <<-SQL
      ORDER BY issue_comments.updated_at DESC
    SQL
    query
  end

  # The user's pull request was reviewed
  def reviews_received_sql
    select_columns = ["issues.id", ":interaction", "pull_request_reviews.submitted_at", "pull_request_reviews.user_id"]
    select_columns << "pull_request_reviews.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
     SELECT #{select_columns}
      FROM pull_request_reviews
      INNER JOIN issues
      ON pull_request_reviews.pull_request_id = issues.pull_request_id
    SQL

    query += <<-SQL
      WHERE issues.user_id = :user_id
      AND pull_request_reviews.submitted_at >= :since
    SQL

    query += <<-SQL
      ORDER BY pull_request_reviews.submitted_at DESC
    SQL
    query
  end

  # User submitted a PR review comment
  def review_comment_sql
    select_columns = [
      "issues.id",
      ":interaction",
      "pull_request_review_comments.updated_at",
      "pull_request_review_comments.user_id",
      "pull_request_review_comments.id"
    ]
    select_columns << "issues.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
      SELECT #{select_columns}
      FROM pull_request_review_comments
      INNER JOIN pull_requests
      ON pull_request_review_comments.pull_request_id = pull_requests.id
      INNER JOIN issues
      ON pull_requests.id = issues.pull_request_id
    SQL

    query += <<-SQL
      WHERE pull_request_review_comments.user_id = :user_id
      AND pull_request_review_comments.updated_at >= :since
    SQL

    query += <<-SQL
      ORDER BY pull_request_review_comments.updated_at DESC
    SQL
    query
  end

  # The user was the author of an issue comment
  def created_issue_comments_sql
    select_columns = [
      "issue_comments.issue_id",
      ":interaction",
      "issue_comments.updated_at",
      "issue_comments.user_id",
      "issue_comments.id"
    ]
    select_columns << "issue_comments.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
      SELECT #{select_columns}
      FROM issue_comments
    SQL

    query += <<-SQL
      WHERE issue_comments.user_id = :user_id
      AND issue_comments.updated_at >= :since
    SQL

    query += <<-SQL
      ORDER BY issue_comments.updated_at DESC
    SQL
    query
  end

  # The user's review was requested on a pull request
  def review_requests_sql
    select_columns = ["issues.id", ":interaction", "review_requests.created_at", "review_requests.id"]
    select_columns << "issues.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
      SELECT #{select_columns}
      FROM review_requests
      INNER JOIN issues
      ON review_requests.pull_request_id = issues.pull_request_id
    SQL

    query += <<-SQL
      WHERE review_requests.reviewer_id = :user_id
      AND review_requests.reviewer_type = 'User'
      AND review_requests.created_at >= :since
      AND review_requests.dismissed_at IS NULL
    SQL

    query += <<-SQL
      ORDER BY review_requests.id DESC
    SQL
    query
  end

  # The user was the actor in some issue event
  def issue_events_sql
    select_columns = ["issue_events.issue_id", "issue_events.event", "issue_events.created_at", "issue_events.id"]
    select_columns << "issue_events.repository_id" if filter_by_organization?
    select_columns = select_columns.join(",")
    query = <<-SQL
      SELECT #{select_columns}
      FROM issue_events
    SQL

    query += <<-SQL
      WHERE issue_events.actor_id = :user_id
      AND issue_events.created_at >= :since
      AND issue_events.event IN (:event_actions)
    SQL

    query += <<-SQL
      ORDER BY issue_events.id DESC
    SQL
    query
  end

  def assigned_issue_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since, interaction: ASSIGNED_INTERACTION)
  end

  def opened_issue_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since, interaction: OPENED_INTERACTION)
  end

  def received_issue_comment_query_args(issue_ids)
    query_args_with_org_ids(since: @since, interaction: RECEIVED_COMMENT_INTERACTION,
                            edit_interaction: RECEIVED_COMMENT_EDITED_INTERACTION,
                            issue_ids: issue_ids)
  end

  def created_issue_comment_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since, interaction: COMMENT_INTERACTION,
                            edit_interaction: COMMENT_EDITED_INTERACTION)
  end

  def review_request_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since,
                            interaction: REVIEW_REQUESTED_INTERACTION)
  end

  def review_received_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since,
                            interaction: REVIEW_RECEIVED_INTERACTION)
  end

  def review_comment_submitted_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since,
                            interaction: REVIEW_COMMENTED_INTERACTION)
  end

  def issue_event_query_args
    query_args_with_org_ids(user_id: @user.id, since: @since, event_actions: EVENT_ACTIONS)
  end

  # Private: Decorates the given hash with an :organization_id key if an organization ID was
  # passed to the Issue::RecentInteractions constructor, and an :excluded_account_ids key
  # if any excluded User/Organization IDs were given.
  #
  # args - a Hash
  #
  # Returns a Hash.
  def query_args_with_org_ids(args)
    args[:organization_id] = @organization_id if @organization_id
    args[:excluded_account_ids] = @excluded_account_ids if @excluded_account_ids.any?
    args
  end

  def user_open_issue_ids
    # Limited to 100 so we can use this in an `IN` clause in another query
    # without having too many IDs in the clause.
    @user.issues.where(state: "open").order("id DESC").limit(100).pluck(:id)
  end

  def get_interactions_by_issue_id(sql_results)
    all_interactions_by_issue_id = sql_results.inject({}) do |hash, row|
      issue_id, interaction, occurred_at, user_id, comment_id = row
      hash[issue_id] ||= []
      hash[issue_id] << { interaction: interaction, occurred_at: occurred_at, user_id: user_id, comment_id: comment_id }
      hash
    end

    # Keep only the latest interaction for a given issue:
    most_recent_interaction_per_issue(all_interactions_by_issue_id)
  end

  def most_recent_interaction_per_issue(all_interactions_by_issue_id)
    all_interactions_by_issue_id.inject({}) do |new_hash, data|
      issue_id, old_hash = data
      new_hash[issue_id] = old_hash.max_by { |hash| hash[:occurred_at] }
      new_hash
    end
  end

  def filter_by_organization?
    @organization_id || @excluded_account_ids.any?
  end
end
