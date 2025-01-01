# typed: true
# frozen_string_literal: true

# ActivitySummaries power the Pulse pages. What's happened on a repository
# for a given time period? What's interesting?
class Repository::ActivitySummary
  include AvatarHelper
  include Scientist

  attr_reader :repo, :viewer, :since, :branch, :period
  attr_reader :merged_pulls, :new_pulls, :active_pulls
  attr_reader :closed_issues, :new_issues, :active_issues
  attr_reader :now

  # Public: initializes an activity summary.
  #
  # viewer  - User viewing the summary.
  # since   - When to summarize from. Absolute int unixtime.
  # period  - Alternative to since, specify a time period name like daily,
  #           halfweekly, weekly, or monthly
  # branch  - Branch to look at for commit summary.
  #
  # Returns an ActivitySummary object.
  def initialize(repo, viewer:, since: nil, period: nil, branch: nil)
    @now = Time.now
    @repo = repo
    @viewer = viewer

    if @since = parse_since(since)
      @period = @now - @since
    elsif @period = parse_period(period)
      @since = @now - @period
    else
      @period = parse_period("weekly")
      @since  = @now - @period
    end

    @branch = branch || @repo.default_branch

    @issues, @pull_requests = fetch_issues_and_pull_requests

    summarize_pulls
    summarize_issues
  end

  # Internal: Parse a period string into the number of seconds away it is.
  #
  # Returns the time duration or nil when no `period` was specified.
  def parse_period(period)
    case period
    when "daily" then 1.day
    when "halfweekly" then 3.days
    when "weekly" then 1.week
    when "monthly" then 1.month
    end
  end

  # Internal: Parse an absolute unixtime value and return the time it
  # represents.
  #
  # Returns a Time object or nil when no `since` was specified.
  def parse_since(since)
    Time.at(since.to_i) if since.present?
  end

  # Public: The number of commits.
  #
  # Returns Integer commits.
  def commit_count
    @commit_count ||= begin
      activity_summary = @repo.rpc.activity_summary_coauthors(@since.to_i)
      activity_summary.select do |(_name, _email), data|
        data[:committed_count] > 0
      end.sum { |(_name, _email), data| data[:committed_count] }
    end
  end

  # Public: Whether the default branch has any commits in the given time range.
  #
  # Returns a Boolean
  def has_default_branch_commits?
    return @has_default_branch_commits if defined?(@has_default_branch_commits)

    @has_default_branch_commits = default_branch_commit_count!(max_count: 1) > 0
  end

  # This is similar
  # Public: The number of commits on the default branch in the given time range.
  # This data is cached up to 6 hours and is also invalidated any time a repository
  # is pushed to.
  #
  # Returns a number of commits
  def default_branch_commit_count
    @default_branch_commit_count ||= cache(default_branch_commit_count_cache_key, ttl: 6.hours) do
      default_branch_commit_count!
    end
  end

  # Public: The largest number of commits by a single individual. 0 if there are
  # no commits.
  #
  # Returns Integer commits by most active user.
  def max_commits
    @max_commits ||= authors_with_commits.collect { |info| info[:commits].to_i }.max || 0
  end

  # All of the committing user names, email addresses, and commit counts. This
  # data is cached for up to six hours and is also invalidated any time a
  # repository is pushed to.
  #
  # Returns an Array of [count, name, email] arrays.
  def committers
    @committers ||=
      cache(committers_cache_key, ttl: 6.hours) { committers! }
  end

  # Internal: Load commit by user summary log data and turn into simple data
  # structure of the form:
  #
  # [[count, name, email], ...]
  #
  # Returns an array of count, name, email arrays.
  def committers!
    activity_summary = @repo.rpc.activity_summary_coauthors(@since.to_i)
    activity_summary.select do |(_name, _email), data|
      data[:authored_count] > 0
    end.map do |(name, email), data|
      [data[:authored_count], name, email]
    end
  rescue ::GitRPC::InvalidRepository
    # We mimic the behaviour of the script itself when it doesn't find the
    # repository
    []
  end

  # Public: Cache key used to store committer commit count information. May be
  # used to check if the data is present in cache.
  def committers_cache_key
    pulse_git_data_cache_key("committers")
  end

  # Internal: Load commit count to default branch within the given range
  #
  # Returns number of commits
  def default_branch_commit_count!(max_count: 10_000)
    default_branch_name = "refs/heads/#{@repo.default_branch}"
    @repo.rpc.count_revision_history(default_branch_name, max_count: max_count, no_merges: true, since_time: @since.to_s)
  rescue GitRPC::BadRevision
    # Handle cases where the default branch does not exist (yet)
    0
  end

  # Public: Cache key used to store commit count to default branch. May be
  # used to check if the data is present in cache.
  def default_branch_commit_count_cache_key
    pulse_git_data_cache_key("default_commit_count")
  end

  # Public: Committer emails.
  #
  # Returns an Array of email Strings.
  def committer_emails
    @committer_emails ||= committers.map { |(_, _, email)| email.downcase }
  end

  # Public: The Users committing to this repository.
  #
  # Returns a Hash of Users, indexed by committer email address
  def committer_users_by_email
    @committer_users_by_email ||= begin
      business = @repo.enterprise_managed_business if @repo.is_enterprise_managed?
      emails_to_users = User.find_by_emails(committer_emails, business: business)
      GitHub::PrefillAssociations.prefill_associations(emails_to_users.values, :profile)
      emails_to_users
    end
  end

  # Public: Users committing to the repo with their total number of commits.
  #
  # Handles accumulating all commits for a given user, even when using
  # different email addresses for commits.
  #
  # Returns an Array of [User, Integer commits] tuples.
  def authors_with_commits
    @authors_with_commits ||=
      begin
        hash = {}
        hash.default = 0
        committers.each do |commits, name, email|
          email.downcase!
          user = committer_users_by_email.detect { |key, _| key.downcase == email }
          user = (user.nil? || UserEmail.generic_domain?(email)) ? { name: name, email: email } : user[1]
          hash[user] += commits
        end
        hash.sort_by { |(_, commits)| commits }.reverse.map do |user, commits|
          if user.is_a?(User)
            name  = user.profile_name
            login = user.login
            email = user.gravatar_email
          else
            name  = user[:name]
            login = nil
            email = user[:email]
          end

          {
            name: name,
            login: login,
            gravatar: login ? avatar_url_for(user) : gravatar_url_for(email, proxied: true),
            commits: commits,
          }.tap do |hash|
            if login
              hash[:hovercard_url] = HovercardHelper.user_hovercard_path(user_login: user.display_login)
            end
          end
        end
      end
  end

  # Public: The diffstat (insertions, deletions, files changed) of the time
  # period for the master branch. Parsed into Integers of files changed,
  # insertions, and deletions.
  #
  # Returns a Hash.
  def diffstat
    @diffstat ||= cache(diffstat_cache_key, ttl: 6.hours) { diffstat! }
  end

  # Internal: Load diffstat information from git repository and return the
  # summarized result.
  #
  # Returns a { :files => int, :insertions => int, :deletions => int } hash.
  def diffstat!
    unless @repo.empty?
      raw = @repo.rpc.diff_shortstat(range)
      files = raw.match /([\d]+) files?/
      insertions = raw.match /([\d]+) insert/
      deletions = raw.match /([\d]+) delet/
    end

    {
      files: files ? files[1].to_i : 0,
      insertions: insertions ? insertions[1].to_i : 0,
      deletions: deletions ? deletions[1].to_i : 0,
    }
  rescue GitRPC::CommandFailed => boom
    msg = boom.message
    raise if !msg.include?("fatal: bad revision") && !msg.match(/fatal: Log .* empty/)

    { files: 0, insertions: 0, deletions: 0 }
  end

  # Public: Cache key used to store files changed / diffstat information. May be
  # used to check if the data is present in cache.
  def diffstat_cache_key
    pulse_git_data_cache_key("diffstat")
  end

  def range
    @range ||= begin
      # return a range based on "since" time if a branch head ref isn't found
      branch_head = @repo.heads.find(branch)
      return "#{branch}@#{since.to_i}...#{branch}" if branch_head.nil?

      # get the commit that was at the branch HEAD at the "since" time
      branch_head_oid = branch_head.target_oid
      commit = @repo.rpc.list_revision_history(branch_head_oid, limit: 1, until: since)
                        .first
      # get a range between the commit and branch HEAD
      "#{commit}...#{branch}"
    end
  end

  # Public: All active discussions that are not New/Closed Issues or
  # New/Closed Pull Requests.
  #
  # Returns a collection of Issues and PullRequest objects along with their
  # comment count as an array of [object, count] arrays.
  def active
    @active ||= (active_issues + active_pulls).map do |o|
      issue = o.try(:issue) || o
      comment_count = issue_comment_counts[issue.id] || 0
      if issue.pull_request?
        comment_count += (review_comment_counts[issue.pull_request_id] || 0)
      end

      [o, comment_count]
    end.sort_by { |t| -t[1] }
  end

  # Public: Are there any pull requests in this summary?
  #
  # Returns a boolean.
  def pull_requests?
    new_pulls.any? || merged_pulls.any?
  end

  # Public: Are there any published releases in this summary?
  #
  # Returns a Boolean.
  def releases?
    releases.any?
  end

  # Public: Gets the published releases for this summary period.
  #
  # Returns an Array of Release objects.
  def releases
    fetch_releases unless @releases
    @releases
  end

  # Given new and merged pull requests, what percent does each take up?
  #
  # Returns a Float from 0-1.
  def pull_ratio
    @pull_ratio ||= {
      new: new_pulls.size.to_f / (new_pulls.size + merged_pulls.size),
      merged: merged_pulls.size.to_f / (new_pulls.size + merged_pulls.size),
    }
  end

  # Given a number of commits, what percent of the highest number of commits by
  # one user does it take up?
  #
  # commits_count - Number of commits to compare against the maximum.
  #
  # Returns a Float from 0-1.
  def commits_ratio(commits_count)
    if max_commits.zero?
      0
    else
      commits_count.to_f / max_commits
    end
  end

  # Given a collection type, how many users have been involved in the
  # collection?
  #
  # collection_type - A Symbol of the collection you want.
  #
  # Returns an Integer.
  def user_count_for(collection_type)
    case collection_type
    when :new_pulls
      new_pulls.collect(&:user_id).uniq.size
    when :merged_pulls
      merged_pulls.collect(&:user_id).uniq.size
    when :new_issues
      new_issues.collect(&:user_id).uniq.size
    when :closed_issues
      IssueEvent.where(issue_id: closed_issues, event: "closed").count("DISTINCT actor_id")
    when :releases
      releases.collect(&:author_id).uniq.size
    else
      0
    end
  end

  # Public: Are there any issues in this summary?
  #
  # Returns a boolean.
  def issues?
    new_issues.any? || closed_issues.any?
  end

  # Given new and closed issues, what percent does each take up?
  #
  # Returns a Float from 0-1.
  def issue_ratio
    @issue_ratio ||= {
      new: new_issues.size.to_f / (new_issues.size + closed_issues.size),
      closed: closed_issues.size.to_f / (new_issues.size + closed_issues.size),
    }
  end

  private

  attr_reader :issues, :pull_requests, :pulls_db, :issues_with_pulls

  # Internal: Retrieve comment counts for all issues active during the time
  # period. Optimized to retrieve all counts in a single query.
  #
  # Returns a hash of issue_id => count mappings.
  def issue_comment_counts
    @issue_comment_counts ||= @viewer.nil? ? 0 : IssueComments::Public.count_by_issue_since(repo.id, since, @viewer)
  end

  # Internal: Retrieve review comment counts for all pull requests active during
  # the time period. Optimized to retrieve all counts in a single query.
  #
  # Returns a hash of issue_id => count mappings.
  def review_comment_counts
    return @pull_request_review_comment_counts if defined? @pull_request_review_comment_counts

    @pull_request_review_comment_counts = PullRequestReviewComment.
      filter_spam_for(@viewer).
      joins("INNER JOIN `issues` ON `issues`.`pull_request_id` = `pull_request_review_comments`.`pull_request_id`").
      where(issues: { repository_id: repo.id }).
      where("`issues`.`updated_at` > ?", since).
      where("`pull_request_review_comments`.`created_at` > ?", since).
      group("`pull_request_review_comments`.`pull_request_id`").
      count
  end

  # Internal: retrieve Pull Requests and Issues with efficient queries
  def fetch_issues_and_pull_requests
    return [[], []] if repo.spammy?

    issues_array = fetch_issues
    pull_requests_array = fetch_pull_requests

    GitHub::PrefillAssociations.prefill_associations(pull_requests_array + issues_array, :user)

    [issues_array, pull_requests_array]
  end

  def fetch_pull_requests
    return [] if repo.spammy?

    # fetch PullRequests *without* including Issues
    pulls = repo.pull_requests.
      where(
        "pull_requests.updated_at > ?",
        since,
      ).
      filter_spam_for(@viewer)
    @pulls_db = pulls

    issues_with_pulls = []

    # get the Issues that go with the pulls above
    if pulls.present?
      pr_issues_where_clause = "issues.pull_request_id in (?)"
      pr_issues_conditions = [pr_issues_where_clause]
      pr_issues_conditions << pulls.map(&:id)

      issues_with_pulls = repo.issues.
        filter_spam_for(@viewer).
        where(pr_issues_conditions)

      @issues_with_pulls = issues_with_pulls

      GitHub::PrefillAssociations.prefill_associations(issues_with_pulls, :pull_request, available_records: pulls.to_a)
    end

    issues_with_pulls.map(&:pull_request)
  end

  def fetch_issues
    return [] if repo.spammy?

    # get all the bare Issues
    bare_issues_where_clause = "issues.pull_request_id is NULL AND issues.updated_at > ?"
    bare_issues_conditions = [bare_issues_where_clause, since]

    bare_issues = repo.issues.
      filter_spam_for(@viewer).
      where(bare_issues_conditions)

    bare_issues.to_a
  end

  def fetch_releases
    @releases = repo.releases.includes(:author).published.where("published_at > ?", since)
  end

  # Summarizes all Pull Requests for an activity summary. Populates several
  # attributes.
  #
  # Returns nothing.
  def summarize_pulls
    results = Scientist.run "sort_and_filter_prs" do |e|
      e.use { original_summarize_pulls }
      e.try { experimental_summarize_pulls }

      e.clean do |value|
        value.to_json(only: [
          :id,
          :repository_id,
          :created_at,
          :merged_at,
        ])
      end
    end

    @merged_pulls = results[0]
    @new_pulls = results[1]
    @active_pulls = results[2]
  end

  def original_summarize_pulls
    merged_pulls, my_pulls = pull_requests.partition { |pull| pull.merged_at && pull.merged_at > since }
    merged_pulls.sort_by! { |pull| -pull.merged_at.to_i }
    new_pulls, active_pulls = my_pulls.reject(&:closed?).partition { |pull| pull.created_at > since }

    [merged_pulls, new_pulls.sort, active_pulls.sort]
  end

  def experimental_summarize_pulls
    merged_pulls = pulls_db ? pulls_db.where("merged_at IS NOT NULL AND merged_at > ?", since).order(merged_at: :desc) : []

    if issues_with_pulls
      open_pr_ids = issues_with_pulls.where(closed_at: nil).pluck(:pull_request_id)
      open_prs = pulls_db.where(id: open_pr_ids, merged_at: nil)

      new_pulls = open_prs.where("created_at > ?", since).order(created_at: :desc)
      active_pulls = open_prs.where("created_at <= ?", since)
    else
      new_pulls, active_pulls = [], []
    end

    [merged_pulls, new_pulls.sort, active_pulls.sort]
  end

  # Summarizes all Issues for an activity summary. Populates several
  # attributes.
  #
  # Returns nothing.
  def summarize_issues
    @closed_issues, my_issues = issues.partition { |issue| issue.closed? && issue.closed_at && issue.closed_at > since }
    @closed_issues.sort_by! { |issue| -issue.closed_at.to_i }
    @new_issues, my_issues = my_issues.partition { |issue| issue.created_at > since }
    @new_issues.sort_by! { |issue| -issue.created_at.to_i }
    @active_issues = my_issues.reject(&:closed?)
  end

  # Internal: cache fetch helper.
  #
  # key     - String cache key.
  # options - Any of :ttl, :force, or :raw.
  # block   - Called when the cache misses. Result is written to cache.
  #
  # Returns the cached value when the cache hits or the value generated by the
  # block when the cache misses.
  def cache(key, options = {}, &block)
    GitHub.cache.fetch(key, options, &block)
  end

  # Internal: generate a cache key for data that may be invalidated by a push.
  # The generated key includes the repository's id and pushed_at timestamp as
  # well as the time period window.
  def pulse_git_data_cache_key(key)
    "pulse:v1:#{repo.id}:#{repo.pushed_at.to_i}:#{period}:#{key}"
  end
end
