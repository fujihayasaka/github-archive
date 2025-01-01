# typed: true
# frozen_string_literal: true

class CommitRecapController < GitContentController
  # This cribs heavily from CommitsController, particularly around initial commit
  # retrieval/params interactions, and may eventually belong there.

  include Commits::HistoryGrouper

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Collab, ApplicationRecord::Configurations, ApplicationRecord::IssuesPullRequests, ApplicationRecord::Repositories, ApplicationRecord::Spokes

  skip_before_action :try_to_expand_path, only: [:show]
  before_action :require_feature_flag
  before_action :set_cache_control_no_store

  sig { void }
  def index
    fix_up_pagination_params!

    commit = repository_commit
    return render_404 unless commit

    commits, _page_info = repository_commits(commit)
    grouped_commits = group_commits(
      commits,
      current_repository,
      params[:name] || current_repository.default_branch, # It's OK if this isn't a branch. This is just for string matching reverse merge commits.
    )

    serialized_groups = serialize_commit_groups_with_prs(grouped_commits)
    render json: serialized_groups
  rescue GitRPC::ObjectMissing, Platform::Errors::Cursor
    render_404
  end

  sig { void }
  def show
    commit_oids = params[:commit_oids]&.split(",") || []
    return render json: { error: "No commit OIDs provided" }, status: :bad_request if commit_oids.empty?

    path = file_path.presence
    diff_entries = []

    commit_oids.each do |oid|
      begin
        commit = Platform::Loaders::GitObject.load(current_repository, oid).sync
        next unless commit

        # Get diff for this commit
        diff = get_commit_diff(commit, path)
        next unless diff

        # Extract diff entries for the specified path
        entries = extract_diff_entries(diff, path)
        diff_entries.concat(entries)
      rescue GitRPC::ObjectMissing, GitRPC::CommandFailed => e
        Rails.logger.warn "Failed to load commit #{oid}: #{e.message}"
        # Continue processing other commits
      end
    end

    render json: { diff_entries: diff_entries }
  end

  sig { void }
  def new
    is_file = false

    path = file_path.presence
    commit = repository_commit

    if path && commit
      begin
        is_file = current_repository.tree_entry(commit.oid, path)&.blob?
      rescue GitRPC::ObjectMissing, GitRPC::CommandFailed => e
        Rails.logger.warn "Failed to check path #{path}: #{e.message}"
      end
    end

    show_popover = user_feature_enabled?(:copilot_commit_recap_new_user_popover) &&
      !current_user&.dismissed_notice?(:copilot_commit_recap_new_user_popover)

    render json: {
      is_file:,
      show_popover:
    }
  end

  private

  sig { void }
  def fix_up_pagination_params!
    if page = params.delete(:page)
      if page.to_i > 1
        params[:after] = Platform::ConnectionWrappers::CursorGenerator.generate_cursor((((page.to_i - 1) * CommitsController::PAGE_SIZE) - 1).to_s)
      end
    end
  end

  def repository_commits(commit = repository_commit, path = file_path.presence, pagination_params: nil)
    pagination_params ||= graphql_pagination_params(page_size: CommitsController::PAGE_SIZE)
    browsing_rename_history = params[:browsing_rename_history]
    arguments = {
      path: path,
      author: author_input,
      since: parsed_since,
      until: parsed_until,
      exclude_parent: ([commit.oid] if browsing_rename_history) || nil,
      commit_oid: commit.oid,
    }

    connection = Platform::ConnectionWrappers::CommitHistory.new(
      commit.repository,
      first: pagination_params[:first],
      last: pagination_params[:last],
      after: pagination_params[:after],
      before: pagination_params[:before],
      arguments: arguments,
      parent: commit,
    )
    [connection.edge_nodes.sync, connection.page_info.sync]
  rescue GitRPC::CommandFailed, GitRPC::Timeout, GitRPC::ObjectMissing, Platform::Errors::Cursor
    [[], nil]
  end

  def repository_commit
    revision = params[:name] || current_repository.default_branch
    if oid = current_repository.ref_to_sha(revision)
      path_prefix = ::Commit.extract_path_prefix_from_expression(revision)
      Platform::Loaders::GitObject.load(current_repository, oid, path_prefix: path_prefix).sync
    end
  end

  def author_input
    if params[:author]
      author = User.find_by_login(params[:author]) || params[:author]

      case author
      when ::User
        { id: author.global_relay_id }
      when ::String
        { emails: [author] }
      when ::Array
        { emails: author.map(&:to_s) }
      end
    end
  end

  def parsed_since
    date = parse_date(params[:since]) or return
    date.at_beginning_of_day.utc
  end

  def parsed_until
    date = parse_date(params[:until]) or return
    # the `until` date is inclusive, so we go until the beginning of the next day
    date += 1.day
    date.at_beginning_of_day.utc
  end

  # Parses a ISO8601 date from a param string into a TimeWithZone at 00:00:00
  # in the current user's time zone
  def parse_date(str)
    date = begin
      Date.iso8601(str)
    rescue ArgumentError
      return
    end
    date.in_time_zone(current_user&.time_zone || Time.zone)
  end

  def require_feature_flag
    render_404 unless current_user&.feature_flag_enabled?(:copilot_commit_recap, default: false)
  end

  # Extract file path from route parameters
  def file_path
    if params[:path].present?
      if params[:path].is_a?(Array)
        params[:path].join("/")
      else
        params[:path].to_s
      end
    end
  end

  sig { params(commit_groups: T::Array[CommitGroup]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialize_commit_groups_with_prs(commit_groups)
    authors = {} # Still sort of an N+1 issue but at least cache per-author

    pr_issues = current_repository.issues.where(number: commit_groups.map(&:pr_number).compact).includes(:pull_request).index_by(&:number)

    commit_groups.map do |group|
      result = {
        type: group.type,
        commits: group.commits.map { |commit| serialize_commit(commit, authors) }
      }
      pr_issue = pr_issues[group.pr_number]
      if pr_issue
        result[:pr] = {
          number: group.pr_number,
          title: pr_issue.title,
          body: pr_issue.compressed_body,
          state: pr_issue.pull_request&.merged? ? "merged" : pr_issue.state,
        }
      end
      result
    end
  end

  sig { params(commit: Commit, authors: T::Hash[String, String]).returns(T::Hash[Symbol, T.untyped]) }
  def serialize_commit(commit, authors)
    author_user = authors[commit.author_email] ||= commit.author
    {
      oid: commit.oid,
      message: commit.message,
      author: {
        login: author_user&.display_login,
        avatar_url: author_user&.primary_avatar_url,
        name: commit.author_name,
        email: commit.author_email,
        date: commit.authored_date
      },
      committer: {
        name: commit.committer_name,
        email: commit.committer_email,
        date: commit.committed_date
      }
    }
  end

  # Get diff for a commit, optionally filtered to a specific path
  sig { params(commit: Commit, path: T.nilable(String)).returns(T.nilable(GitHub::Diff)) }
  def get_commit_diff(commit, path = nil)
    return nil unless commit.parent_oids.any?

    # For merge commits, compare with the first parent
    parent_oid = commit.parent_oids.first

    # Create diff between parent and commit
    diff = GitHub::Diff.new(
      current_repository,
      parent_oid,
      commit.oid,
      {
        ignore_whitespace: false,
        max_total_lines: 5000, # Reasonable limit for diff analysis
        max_diff_lines: 1000
      }
    )

    # Add path filter if specified
    diff.add_path(path) if path.present?

    diff
  rescue GitRPC::ObjectMissing, GitRPC::CommandFailed => e
    Rails.logger.warn "Failed to create diff for commit #{commit.oid}: #{e.message}"
    nil
  end

  # Extract diff entries from a diff, optionally filtered to a specific path
  sig { params(diff: GitHub::Diff, path: T.nilable(String)).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def extract_diff_entries(diff, path = nil)
    entries = []

    diff.each do |entry|
      # If path is specified, only include entries that match the path
      next if path.present? && !path_matches_entry(path, entry)

      entry_data = {
        old_path: entry.a_path,
        new_path: entry.b_path,
        additions: entry.additions,
        deletions: entry.deletions,
        status: entry.status,
        text: entry.text.presence # Include diff text if available and not too large
      }

      # Limit text size to avoid overwhelming the API
      if entry_data[:text] && entry_data[:text].length > 10_000
        entry_data[:text] = entry_data[:text][0, 10_000] + "\n... (truncated)"
      end

      entries << entry_data
    end

    entries
  rescue GitRPC::ObjectMissing, GitRPC::CommandFailed => e
    []
  end

  # Check if a path matches a diff entry (handles renames)
  sig { params(path: String, entry: T.untyped).returns(T::Boolean) }
  def path_matches_entry(path, entry)
    entry.a_path == path || entry.b_path == path
  end
end
