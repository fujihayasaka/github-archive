# typed: strict
# frozen_string_literal: true

class Copilot::CiAnalysisController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::RateLimitedRequest

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:show],
  )

  allow_verified_fetch only: [:apply_suggestions, :show]

  before_action :login_required
  before_action :require_ci_analysis_enabled
  before_action :parse_json_params, only: [:apply_suggestions]
  before_action :require_xhr, only: [:show]

  NEWLINE_REGEXP = T.let(Regexp.union(["\r\n", "\r", "\n"]), Regexp)
  MAX_HUNKS = 50
  READ_RATE_LIMIT = 400

  rate_limit_requests \
    only: [:show],
    max: READ_RATE_LIMIT,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    key: :default_rate_limit_key,
    at_limit: :render_rate_limited_response

  # Maps exception classes from DiffEntrySuggestedChange and diff parsing
  # to HTTP status codes. Checked most-specific first since ConflictError
  # inherits from UnprocessableError.
  ERROR_STATUS_MAP = T.let([
    [DiffEntrySuggestedChange::ConflictError, :conflict],
    [DiffEntrySuggestedChange::NotFoundError, :not_found],
    [DiffEntrySuggestedChange::ForbiddenError, :forbidden],
    [DiffEntrySuggestedChange::UnprocessableError, :unprocessable_entity],
    [ReviewComments::Suggestion::ParseError, :unprocessable_entity],
  ].freeze, T::Array[[T.class_of(StandardError), Symbol]])

  # GET /pull/:pull/page_data/ci_findings
  # Serves CI failure analysis findings for the mergebox checks section.
  sig { void }
  def show
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    head_sha = pull_request.head_sha
    return render json: { ciFindings: [] }, status: :ok if head_sha.blank?

    capi = ::Copilot::User.copilot_api(
      user: current_user,
      integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
      session: user_session,
      real_ip: request.remote_ip,
    )

    capi_response = capi.get_ci_findings(
      head_sha: head_sha,
      repo_id: current_repository.id,
    )

    enrich_ci_findings_with_original_content(T.cast(capi_response, ActiveSupport::HashWithIndifferentAccess), head_sha)

    render json: capi_response, status: :ok
  rescue CopilotAPI::NotFoundError
    render json: { ciFindings: [] }, status: :ok
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  sig { void }
  def apply_suggestions # rubocop:disable GitHub/UseRestfulActions
    pull_request = find_pr_by_number(params[:pull].to_i)
    return render_error(:not_found, "Pull request not found") if pull_request.nil?
    return render_error(:not_found, "Pull request not found") if pull_request.hide_from_user?(current_user)

    fix_diff_hunks = params[:fix_diff_hunks]
    return render_error(:bad_request, "fix_diff_hunks is required and must be a non-empty array") unless fix_diff_hunks.is_a?(Array) && fix_diff_hunks.present?
    return render_error(:bad_request, "Too many hunks (max #{MAX_HUNKS})") if fix_diff_hunks.size > MAX_HUNKS

    head_repo = pull_request.head_repository
    return render_error(:unprocessable_entity, "Head repository not found") if head_repo.nil?

    commit_message = params[:commit_message].presence ||
      "Apply #{fix_diff_hunks.size} CI fix suggestion#{"s" if fix_diff_hunks.size != 1} from Copilot"

    diff_entries = build_diff_entries_from_hunks(pull_request, head_repo, fix_diff_hunks)
    return render_error(:unprocessable_entity, "No valid diff entries could be built") if diff_entries.empty?

    suggested_change = DiffEntrySuggestedChange.new(
      repository: head_repo,
      pull_request: pull_request,
      diff_entries: diff_entries,
    )

    commit_result = suggested_change.commit_change_for_user(
      author: current_user,
      current_oid: pull_request.head_sha,
      message: commit_message,
      sign: true,
      co_author_note: "Co-authored-by: Copilot <noreply@github.com>",
      reflog_data: {
        repo_name: head_repo.name_with_display_owner,
        repo_public: head_repo.public?,
        user_login: current_user.display_login,
        from: GitHub.context[:from],
        via: "ci analysis direct fix",
      },
    )

    commit_oid = commit_result&.first
    finding_ids = (params[:finding_ids] || []).compact

    GitHub.dogstats.increment("ci_analysis.apply_suggestions.success")
    render json: { commit_oid: commit_oid, finding_ids: finding_ids }, status: :ok
  rescue DiffEntrySuggestedChange::Error, ReviewComments::Suggestion::ParseError => e
    status = status_for_exception(e)
    render_error(status, e.message, exception: e)
  end

  private

  sig { void }
  def require_ci_analysis_enabled
    unless FeatureFlag.vexi.enabled?(:validation_platform_ci_analysis_check_runs_enabled, current_repository, default: false)
      head :not_found
    end
  end

  sig { void }
  def require_xhr
    head(:not_acceptable) unless request&.xhr? || current_user&.employee?
  end

  sig { params(status: Symbol, message: String, exception: T.nilable(StandardError)).void }
  def render_error(status, message, exception: nil)
    GitHub.dogstats.increment("ci_analysis.apply_suggestions.error", tags: ["status:#{status}"])
    if exception
      GitHub.logger.error("CI analysis apply_suggestions error", "gh.error_class": exception.class.name, "gh.status": status, exception: exception)
    else
      GitHub.logger.warn("CI analysis apply_suggestions error", "gh.error_message": message, "gh.status": status)
    end
    render json: { error: message }, status: status
  end

  sig { params(exception: StandardError).returns(Symbol) }
  def status_for_exception(exception)
    ERROR_STATUS_MAP.each do |(klass, status)|
      return status if exception.is_a?(klass)
    end
    :internal_server_error
  end

  sig { void }
  def render_rate_limited_response
    render status: :too_many_requests, json: { error: "Your browser sent requests too quickly" }
  end

  # Enriches CI findings fixDiffHunks with the original source content so the
  # frontend can render a full deletion/addition diff instead of placeholder text.
  sig { params(capi_response: ActiveSupport::HashWithIndifferentAccess, head_sha: String).void }
  def enrich_ci_findings_with_original_content(capi_response, head_sha)
    findings = capi_response[:ciFindings]
    return unless findings.is_a?(Array)

    blob_cache = {}

    findings.each do |finding|
      hunks = finding[:fixDiffHunks]
      next unless hunks.is_a?(Array)

      hunks.each do |hunk|
        file_path = hunk[:filePath]
        start_line = hunk[:startLine]
        end_line = hunk[:endLine]
        next if file_path.blank? || start_line.nil? || end_line.nil?

        blob_content = if blob_cache.key?(file_path)
          blob_cache[file_path]
        else
          blob_cache[file_path] = fetch_blob_lines(file_path, head_sha)
        end
        next if blob_content.nil?

        original_lines = blob_content[start_line - 1, end_line - start_line + 1]
        next if original_lines.nil?

        hunk[:originalContent] = original_lines.join("\n")
      end
    end
  rescue => e
    Rails.logger.warn("Failed to enrich CI findings with original content: #{e.message}")
    GitHub.dogstats.increment("ci_findings.enrich_original_content.error", tags: ["error:#{e.class.name&.demodulize}"])
  end

  # Fetches the content of a file at a given SHA and returns it as an array of lines.
  sig { params(file_path: String, head_sha: String).returns(T.nilable(T::Array[String])) }
  def fetch_blob_lines(file_path, head_sha)
    blob = current_repository.blob(head_sha, file_path)
    return nil if blob.nil? || blob.binary?

    blob.data&.lines&.map(&:chomp)
  end

  sig { params(pull_request: PullRequest, head_repo: Repository, hunks: T.untyped).returns(T::Array[GitHub::Diff::Entry]) }
  def build_diff_entries_from_hunks(pull_request, head_repo, hunks)
    hunks.flat_map do |hunk|
      file_path = hunk["filePath"]
      start_line = hunk["startLine"].to_i
      end_line = hunk["endLine"].to_i
      suggestion_text = hunk["suggestion"].to_s

      next [] if file_path.blank? || start_line < 1 || end_line < start_line

      blob = head_repo.blob(pull_request.head_sha, file_path, { truncate: false, limit: 1.megabyte })
      next [] if blob.blank?

      source_lines = blob.data.split(NEWLINE_REGEXP, -1)

      first_idx = start_line - 1
      last_idx = end_line - 1
      next [] if first_idx < 0 || last_idx >= source_lines.length

      original_lines = source_lines[first_idx..last_idx] || []
      new_lines = suggestion_text.empty? ? [] : suggestion_text.split("\n", -1)

      # TODO: build_unified_diff is private in UserCommentSuggestion. Extract to
      # a shared utility so we don't rely on .send to bypass encapsulation.
      # See: https://github.com/github/copilot-code-review/issues/2626
      diff_content = ReviewComments::UserCommentSuggestion.send(
        :build_unified_diff,
        path: file_path,
        start_line: start_line,
        original_lines: original_lines,
        new_lines: new_lines,
      )

      entries = []
      parser = GitHub::Diff::Parser.new(diff_content)
      parser.each { |entry| entries << entry }
      entries
    rescue GitHub::Diff::Parser::UnrecognizedText => e
      GitHub.dogstats.increment("ci_analysis.build_diff.parse_error", tags: ["file_ext:#{File.extname(file_path.to_s)}"])
      GitHub.logger.error("CI analysis direct fix: failed to parse diff", "gh.file_path": file_path, exception: e)
      []
    end
  end

  sig { params(number: Integer).returns(T.nilable(PullRequest)) }
  def find_pr_by_number(number)
    current_repository.issues.find_by_number(number).try(:pull_request)
  end
end
