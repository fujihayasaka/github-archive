# typed: true
# frozen_string_literal: true

class HypersightController < AbstractRepositoryController
  include Commit::ReactDiffLinesHelper
  include Commit::ReactPayloadDataDependency

  before_action :require_feature

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  class UrlsData < T::Struct
    const :checks, String
    const :commits, String
    const :conversation, T.nilable(String)
    const :files, String
    const :walkthrough, String
  end

  def show
    pr = find_pull_request
    comparison = pr.historical_comparison

    start_oid, end_oid = pr.merge_base, pr.head_sha

    if start_oid && end_oid
      start_commit, end_commit = pr.compare_repository.commits.find([start_oid, end_oid])

      diff_options = {
        base_repository: pr.base_repository,
        head_repository: pr.head_repository,
      }
      diff = GitHub::Diff.new(current_repository, pr.merge_base, pr.head_sha, diff_options)
    end

    pr_data = build_pr_data(pr, comparison)
    pr_base_url = pr.permalink(include_host: false)

    diffs = build_file_diff_payload(
      ::Diff::FileListView.new(
        commit: end_commit,
        diffs: diff,
        current_user: current_user
      ),
      0
    ).as_json(only: ALLOWED_DIFF_JSON_FIELDS)

    render_react_app(
      payload: {
        pullRequest: pr_data,
        mentionedIssues: mentioned_issues(pr),
        apiUrl: copilot_api_url,
        diffs: analyze_diff(pr, diffs),
        urls: UrlsData.new(
          checks: "#{pr_base_url}/checks",
          commits: "#{pr_base_url}/commits",
          conversation: pr_base_url,
          files: "#{pr_base_url}/files",
          walkthrough: "#{pr_base_url}/walkthrough",
        ),
      },
      title: "Hypersight",
    )
  end

  private

  def analyze_diff(pull, diffs)
    diff_analysis = ::WorkspaceEditor::DiffAnalysisClient.analyze(
      pull: pull,
      current_user: current_user,
      categorize: true,
    )

    return nil unless diff_analysis && diff_analysis[:diff_metadata].present?

    categorized_diffs = diff_analysis[:diff_metadata]

    diffs_by_path = diffs.index_by { |diff| diff["path"] }

    categorized_diffs.each_with_object({}) do |categorized_diff, result|
      path = categorized_diff[:path]
      category = categorized_diff[:category]
      full_diff = diffs_by_path[path]
      full_diff["risk"] = categorized_diff[:diff_hunks]&.map { |hunk| hunk[:risk] }&.max
      category_list = result[category]
      if !category_list
        category_list = []
        result[category] = category_list
      end

      category_list.push(full_diff)
    end
  rescue Faraday::ConnectionFailed => e
    # If we can't hit the diff analysis service, consider all changes to be code,
    # so we can at least continue to generate a walkthrough.
    {
      "CODE" => diffs,
    }
  end

  def require_feature
    render_404 unless current_user&.feature_flag_enabled?(:hypersight, default: false)
  end

  memoize def copilot_api_url
    with_database_error_fallback(fallback: "") do
      Copilot::SKUIsolation.for_user(current_user).api.endpoint
    end
  end

  def find_pull_request
    PullRequest.with_number_and_repo(
      params[:id].to_i,
      current_repository,
      include: [:user, :base_repository, :base_user, :head_repository, :head_user]
    )
  end

  def build_pr_data(pr, comparison)
    {
      number: pr.number,
      title: pr.title,
      user: {
        login: pr.user.display_login,
        id: pr.user.id,
        avatar_url: pr.user.primary_avatar_url(64),
      },
      created_at: pr.created_at.iso8601,
      updated_at: pr.updated_at.iso8601,
      state: pr.state.to_s,
      html_url: pr.url,
      id: pr.id,
      body: pr.body,
      changed_files: pr.changed_files,
      commits: comparison.commits.count,
      base: {
        ref: pr.base_ref,
        repo: {
          name: pr.base_repository.name,
          owner: { login: pr.base_repository.owner.name }
        }
      },
      head: {
        ref: pr.head_ref,
        repo: {
          name: pr.head_repository.name,
          owner: { login: pr.head_user.display_login }
        }
      }
    }
  end

  def mentioned_issues(pr)
    # Load all issues that this PR "closes" that the user has access to (respecting CAP)
    issues = pr.cap_filtered_close_issue_references_for(viewer: current_user, cap_filter:).first(5)
    issues.map do |issue|
      {
        number: issue.number,
        title: issue.title,
        body: issue.body,
        repo: {
          name: issue.repository.name,
          owner: { login: issue.repository.owner.name }
        }
      }
    end
  end

  def build_file_diff_payload(file_list_view, start_index, short_path = nil)
    file_views, new_tree_entries, old_tree_entries, highlighted_diff = get_prefilled_tree_entries(file_list_view)

    file_views.map do |diff|
      current_diff_entry = diff.diff

      shd = highlighted_diff.colorized_lines(current_diff_entry)
      if shd
        shd.each(&:freeze)
        shd.freeze
      end

      diff_lines = build_diff_line_data(current_diff_entry, shd)
      {
        diffLines: diff_lines,
        isBinary: current_diff_entry.binary?,
        isTooBig: current_diff_entry.too_big?,
        path: current_diff_entry.path,
        status: current_diff_entry.status_label.upcase,
      }
    end
  end
end
