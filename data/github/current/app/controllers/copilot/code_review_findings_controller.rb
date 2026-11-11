# typed: strict
# frozen_string_literal: true

class Copilot::CodeReviewFindingsController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Copilot::CodeReviewFixConcern
  include PullRequests::OverviewHelper

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IssuesPullRequests,
    only: [:index],
  )

  before_action :login_required
  before_action :require_findings_ui_enabled
  before_action :code_review_access_required
  before_action :require_copilot_swe_agent_enabled

  before_action :parse_json_params, only: [:fix, :ignore, :unignore]
  allow_verified_fetch only: [:fix, :ignore, :unignore, :index, :feedback]

  MAX_FIX_ENTITIES = 50
  MAX_INSTRUCTIONS_LENGTH = 1024
  MAX_FINDING_FILE_PATH_LENGTH = 1_024
  MAX_FINDING_FILE_PATH_SEGMENTS = 40
  FEEDBACK_BANNER_NOTICE = T.let("copilot_code_review_findings_feedback_banner", String)
  WORKSPACE_FILE_PATH_PATTERN = T.let(%r{\A(?:(?:\.\./)+|/)*workspaces?/([^/]+)/(.+)\z}, Regexp)
  FINDING_FILE_PATH_URL_PATTERN = T.let(/\A[a-z][a-z0-9+\-.]*:\/\//i, Regexp)
  FINDING_FILE_PATH_WINDOWS_DRIVE_PATTERN = T.let(/\A[A-Za-z]:\//, Regexp)
  FINDING_FILE_PATH_CONTROL_CHAR_PATTERN = T.let(/[[:cntrl:]]/, Regexp)
  FINDING_FILE_PATH_EXTENSIONLESS_ALLOWLIST = T.let(
    Set["Makefile", "Dockerfile", "CODEOWNERS", "LICENSE", "NOTICE", "AUTHORS", "CHANGELOG", "README", "Rakefile", "Gemfile", "Procfile"].freeze,
    T::Set[String],
  )
  CHECK_RUN_SOURCE_TYPES = T.let(Set["check_suite", "pull_request_backfill", "ci_analysis", "ci_failure_analysis"].freeze, T::Set[String])
  COMMENT_SOURCE_TYPES = T.let(Set["pr_review_comment", "pr_timeline_comment", "ccr_review_comment"].freeze, T::Set[String])
  FINDING_FILE_URL_OMITTED_METRIC = T.let("copilot.code_review.findings.file_url_omitted", String)
  FINDING_SOURCE_TELEMETRY_ALLOWLIST = T.let((CHECK_RUN_SOURCE_TYPES + COMMENT_SOURCE_TYPES + Set["code_scanning"]).freeze, T::Set[String])
  FINDINGS_VIEW_ALLOWLIST = T.let(Set["pr"].freeze, T::Set[String])

  sig { void }
  def index
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    capi_response = fetch_findings_from_capi(pull_request, view: effective_findings_view)

    freshness = capi_response[:freshness] || capi_response[:currentFreshness] || "current"
    if freshness != "current"
      retry_after = capi_response[:_retry_after_header].presence || "10"
      response.set_header("Retry-After", retry_after)
    end

    findings = capi_response[:findings] || []
    pr_changed_paths = pull_request_changed_paths(pull_request)
    findings.each do |finding|
      finding["filePath"] = normalize_finding_file_path(finding["filePath"])
      finding["fileUrl"] = build_finding_file_url(finding, pull_request, pr_changed_paths)
      enrich_finding_source_reference_labels(finding) if finding["fileUrl"].blank?
    end

    enrich_findings_with_source_author(findings, pull_request)
    enrich_findings_with_comment_previews(findings, pull_request)

    payload = {
      findings: findings,
      freshness: freshness,
      version: capi_response[:version] || capi_response[:currentVersion] || 1,
      processedVersion: capi_response[:processedVersion] || capi_response[:currentProcessedVersion] || 1,
      pullRequestBasePath: pull_request.path_uri.to_s,
      modelsUrl: findings_models_url(pull_request),
      showFeedbackBanner: show_feedback_banner?,
      feedbackBannerDismissPath: dismiss_notice_path(FEEDBACK_BANNER_NOTICE),
      mergeReadiness: merge_readiness_for(pull_request),
    }

    render json: payload, status: :ok
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CopilotAPI::NotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  sig { void }
  def fix # rubocop:disable GitHub/UseRestfulActions
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    findings = params[:findings]
    return head(:bad_request) unless findings.is_a?(Array) && findings.present?
    return head(:bad_request) if findings.size > MAX_FIX_ENTITIES

    instructions = params[:instructions].presence
    return head(:bad_request) if instructions.present? && (!instructions.is_a?(String) || instructions.length > MAX_INSTRUCTIONS_LENGTH)

    create_pull_request = ActiveModel::Type::Boolean.new.cast(params[:create_pull_request]) || false
    model = params[:model].presence

    problem_statement = build_findings_problem_statement(findings, instructions: instructions)
    task = create_code_review_fix_task(
      pull_request,
      problem_statement: problem_statement,
      create_pull_request: create_pull_request,
      entry_point: :code_review_findings_fix,
      event_type: "code_review_finding_fix",
      model: model,
    )
    task_url = repo_task_path(current_repository.owner, current_repository, task.id)

    finding_ids = findings.map { |f| f["id"] }.compact

    batch_update_findings(pull_request, finding_ids) { |id| { findingId: id, ccaTaskId: task.id } }

    render json: { task_id: task.id, task_url: task_url, finding_ids: finding_ids }, status: :created
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def feedback # rubocop:disable GitHub/UseRestfulActions
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    finding_id = params[:finding_id]
    return head(:bad_request) if finding_id.blank?

    feedback_value = params[:feedback]
    return head(:bad_request) unless %w[POSITIVE NEGATIVE].include?(feedback_value)

    PullRequests::Copilot::instrument_code_review_feedback(
      request_id: GitHub.context[:request_id],
      organization_id: current_repository.owner.is_a?(Organization) ? current_repository.owner.id : nil,
      repository_id: current_repository.id,
      pull_request_id: pull_request.id,
      comment_id: finding_id,
      analytics_tracking_id: current_user.analytics_tracking_id,
      feedback: feedback_value,
      feedback_choice: params[:feedback_choice],
      text_response: params[:text_response],
      custom_instructions_included: false,
      copilot_access_type: current_copilot_user_v2.access_type,
      feedback_target: "FINDING",
    )

    head :created
  end

  sig { void }
  def ignore # rubocop:disable GitHub/UseRestfulActions
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    entity_ids = params[:entity_ids]
    return head(:bad_request) unless entity_ids.is_a?(Array) && entity_ids.present?
    return head(:bad_request) unless entity_ids.all? { |id| id.is_a?(String) && id.present? }

    resolved_at = Time.now.to_i
    resolver_id = current_user.id.to_s
    batch_update_findings(pull_request, entity_ids) do |id|
      { findingId: id, resolvedReason: "wont_fix", resolvedAt: resolved_at, resolverId: resolver_id }
    end
    head :ok
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def unignore # rubocop:disable GitHub/UseRestfulActions
    pull_request = find_pr_by_number(params[:pull].to_i)
    return head(:not_found) if pull_request.nil?
    return head(:not_found) if pull_request.hide_from_user?(current_user)

    entity_ids = params[:entity_ids]
    return head(:bad_request) unless entity_ids.is_a?(Array) && entity_ids.present?
    return head(:bad_request) unless entity_ids.all? { |id| id.is_a?(String) && id.present? }

    batch_update_findings(pull_request, entity_ids) do |id|
      { findingId: id, resolvedReason: nil, resolvedAt: nil, resolverId: nil }
    end
    head :ok
  rescue CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CopilotAPI::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  sig { params(pull_request: PullRequest, ids: T::Array[String], block: T.proc.params(id: String).returns(T::Hash[Symbol, T.untyped])).void }
  def batch_update_findings(pull_request, ids, &block)
    capi = findings_capi
    capi.batch_update_findings(
      repo_id: current_repository.id,
      pull_request_id: pull_request.id,
      head_sha: pull_request.head_sha,
      updates: ids.map { |id| block.call(id) },
    )
  end

  sig { returns(Copilot::User::CopilotApi) }
  def findings_capi
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :code_review_findings_update,
      user_session: user_session,
    )

    Copilot::User::CopilotApi.new(
      current_user,
      integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
      session: user_session,
      real_ip: request.remote_ip,
      token: token,
    )
  end

  sig { params(number: Integer).returns(T.nilable(PullRequest)) }
  def find_pr_by_number(number)
    current_repository.issues.find_by_number(number).try(:pull_request) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { params(findings: T::Array[T::Hash[String, T.untyped]], instructions: T.nilable(String)).returns(String) }
  def build_findings_problem_statement(findings, instructions: nil)
    if findings.size == 1
      f = T.must(findings.first)
      build_finding_problem_statement(
        message: f["message"].to_s,
        file_path: f["filePath"],
        start_line: f["startLine"],
        end_line: f["endLine"],
        instructions: instructions,
      )
    else
      parts = T.let(["Fix the following #{findings.size} code review findings:"], T::Array[String])
      findings.each_with_index do |f, index|
        parts << "---\n\n### Finding #{index + 1}\n\n#{build_finding_problem_statement(
          message: f["message"].to_s,
          file_path: f["filePath"],
          start_line: f["startLine"],
          end_line: f["endLine"],
        )}"
      end
      statement = parts.join("\n\n")
      statement += "\n\n---\n\n### Additional Instructions\n\n#{instructions}" if instructions.present?
      statement
    end
  end

  sig { params(pull_request: PullRequest, view: T.nilable(String)).returns(ActiveSupport::HashWithIndifferentAccess) }
  def fetch_findings_from_capi(pull_request, view: nil)
    loader = PullRequests::Copilot::FindingsLoader.new(
      user: current_user,
      user_session: user_session,
      remote_ip: request.remote_ip,
      entry_point: :code_review_findings_index,
    )
    loader.fetch_findings(pull_request, view: view)
  end

  sig { returns(T.nilable(String)) }
  def effective_findings_view
    param = params[:view].to_s
    param if FINDINGS_VIEW_ALLOWLIST.include?(param)
  end

  sig { params(pull_request: PullRequest).returns(T.nilable(String)) }
  def merge_readiness_for(pull_request)
    latest_run = PullRequests::Copilot::CcrDecisionRunStore
      .runs_for_pull_request(pull_request_id: pull_request.id)
      .last

    latest_run&.approval_readiness_code
  end

  sig do
    params(
      message: String,
      file_path: T.nilable(String),
      start_line: T.nilable(T.any(String, Integer)),
      end_line: T.nilable(T.any(String, Integer)),
      instructions: T.nilable(String),
    ).returns(String)
  end
  def build_finding_problem_statement(message:, file_path: nil, start_line: nil, end_line: nil, instructions: nil)
    parts = T.let(["Fix the following code review finding:"], T::Array[String])
    parts << message

    normalized_file_path = normalize_finding_file_path(file_path)
    if normalized_file_path.present?
      location = +"File: `#{normalized_file_path}`"
      if start_line.present?
        location << if end_line.present? && end_line.to_s != start_line.to_s
          ", Lines: #{start_line}-#{end_line}"
        else
          ", Line: #{start_line}"
        end
      end
      parts << location
    end

    if instructions.present?
      parts << "---\n\n### Additional Instructions\n\n#{instructions}"
    end

    parts.join("\n\n")
  end

  sig { params(file_path: T.nilable(String)).returns(String) }
  def normalize_finding_file_path(file_path)
    original_path = file_path.to_s
    return original_path if original_path.blank?

    normalized_separators = original_path.tr("\\", "/")
    match = WORKSPACE_FILE_PATH_PATTERN.match(normalized_separators)
    return original_path if match.nil?

    workspace_owner = T.must(match[1])
    return original_path unless workspace_owner.casecmp?(current_repository.owner_display_login)

    repository_relative_path = T.must(match[2])
    return original_path if repository_relative_path.blank? ||
      repository_relative_path.start_with?("../") ||
      repository_relative_path.start_with?("/")

    repository_relative_path
  end

  sig { params(pull_request: PullRequest).returns(T::Set[String]) }
  def pull_request_changed_paths(pull_request)
    comparison = pull_request.historical_comparison
    diffs = comparison.diffs
    return Set.new unless diffs.available?

    paths = Set.new
    diffs.entries.each { |entry| paths.add(entry.path) }
    paths
  end

  sig do
    params(
      finding: T::Hash[String, T.untyped],
      pull_request: PullRequest,
      pr_changed_paths: T::Set[String],
    ).returns(T.nilable(String))
  end
  def build_finding_file_url(finding, pull_request, pr_changed_paths)
    original_file_path = finding["filePath"].to_s
    validation = safe_finding_file_path_result(
      original_file_path,
      allow_bare_file: pr_changed_paths.include?(original_file_path.strip.delete_prefix("./")),
    )
    file_path = validation[:file_path]
    omission_reason = validation[:omission_reason]
    if omission_reason.present?
      instrument_finding_file_url_omitted(finding, omission_reason)
      return nil
    end

    file_path = T.must(file_path)

    start_line = finding["startLine"].to_i
    end_line = finding["endLine"].to_i

    if pr_changed_paths.include?(file_path)
      anchor = helpers.diff_path_anchor(file_path)
      anchor += "R#{start_line}" if start_line > 0
      "#{pull_request.path_uri}/changes##{anchor}"
    else
      line_fragment = build_line_fragment(start_line, end_line)
      "/#{current_repository.name_with_display_owner}/blob/#{pull_request.head_sha}/#{UrlHelper.escape_branch(file_path)}#{line_fragment}"
    end
  end

  sig { params(file_path: String, allow_bare_file: T::Boolean).returns(T::Hash[Symbol, T.nilable(String)]) }
  def safe_finding_file_path_result(file_path, allow_bare_file: false)
    path = file_path.strip
    return finding_file_path_result(nil, "blank") if path.blank?
    return finding_file_path_result(nil, "too_long") if path.length > MAX_FINDING_FILE_PATH_LENGTH
    return finding_file_path_result(nil, "control_char") if FINDING_FILE_PATH_CONTROL_CHAR_PATTERN.match?(path)
    return finding_file_path_result(nil, "url_like") if FINDING_FILE_PATH_URL_PATTERN.match?(path)
    return finding_file_path_result(nil, "test_title") if path.include?(" › ")

    normalized_path = path.tr("\\", "/")
    return finding_file_path_result(nil, "windows_drive") if FINDING_FILE_PATH_WINDOWS_DRIVE_PATTERN.match?(normalized_path)
    return finding_file_path_result(nil, "absolute") if normalized_path.start_with?("/")
    return finding_file_path_result(nil, "trailing_slash") if normalized_path.end_with?("/")

    normalized_path = normalized_path.delete_prefix("./") while normalized_path.start_with?("./")
    return finding_file_path_result(nil, "blank") if normalized_path.blank?
    return finding_file_path_result(nil, "too_long") if normalized_path.length > MAX_FINDING_FILE_PATH_LENGTH

    segments = normalized_path.split("/")
    return finding_file_path_result(nil, "too_many_segments") if segments.length > MAX_FINDING_FILE_PATH_SEGMENTS
    return finding_file_path_result(nil, "traversal") if segments.any? { |segment| segment.blank? || segment == "." || segment == ".." }
    first_segment = T.must(segments.first)
    return finding_file_path_result(nil, "workspace_prefix") if first_segment == "workspace" || first_segment == "workspaces"
    return finding_file_path_result(nil, "workspace_prefix") if first_segment == "__w" || segments.first(2) == %w[home runner]
    return finding_file_path_result(nil, "bare_directory") if normalized_path == ".github"

    if segments.length == 1 && !first_segment.include?(".") && !FINDING_FILE_PATH_EXTENSIONLESS_ALLOWLIST.include?(first_segment)
      return finding_file_path_result(nil, "bare_directory") unless allow_bare_file
    end

    finding_file_path_result(normalized_path, nil)
  end

  sig { params(file_path: T.nilable(String), omission_reason: T.nilable(String)).returns(T::Hash[Symbol, T.nilable(String)]) }
  def finding_file_path_result(file_path, omission_reason)
    { file_path: file_path, omission_reason: omission_reason }
  end

  sig { params(finding: T::Hash[String, T.untyped]).void }
  def enrich_finding_source_reference_labels(finding)
    refs = finding["sourceReferences"]
    return unless refs.is_a?(Array)

    refs.each do |ref|
      next unless ref.is_a?(Hash)

      trusted_url = trusted_finding_source_url(ref["url"].to_s)
      next if trusted_url.nil?

      ref["linkLabel"] = finding_source_link_label(ref["source"].to_s)
    end
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def trusted_finding_source_url(url)
    uri = Addressable::URI.parse(url)
    return nil unless uri.scheme == "https"
    return nil unless uri.host == "github.com"

    uri.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end

  sig { params(source: String).returns(String) }
  def finding_source_link_label(source)
    return "View source run" if CHECK_RUN_SOURCE_TYPES.include?(source)
    return "View source comment" if COMMENT_SOURCE_TYPES.include?(source)

    "View source"
  end

  sig { params(finding: T::Hash[String, T.untyped], reason: String).void }
  def instrument_finding_file_url_omitted(finding, reason)
    source = finding_primary_source(finding)
    source = "other" unless FINDING_SOURCE_TELEMETRY_ALLOWLIST.include?(source)

    GitHub.dogstats.increment(FINDING_FILE_URL_OMITTED_METRIC, tags: ["source:#{source}", "reason:#{reason}"])
  end

  sig { params(finding: T::Hash[String, T.untyped]).returns(String) }
  def finding_primary_source(finding)
    refs = finding["sourceReferences"]
    if refs.is_a?(Array) && refs.first.is_a?(Hash)
      source = refs.first["source"].to_s
      return source if source.present?
    end

    "unknown"
  end

  sig { params(start_line: Integer, end_line: Integer).returns(String) }
  def build_line_fragment(start_line, end_line)
    return "" if start_line <= 0 && end_line <= 0

    effective_start = start_line > 0 ? start_line : end_line
    effective_end = end_line > 0 ? end_line : start_line
    if effective_start == effective_end
      "#L#{effective_start}"
    else
      "#L#{effective_start}-L#{effective_end}"
    end
  end

  sig { void }
  def require_findings_ui_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_code_review_findings_ui, current_user, default: false) ||
      pr_overview_feature_enabled_for_user?(current_user, params)
  end

  sig { returns(T::Boolean) }
  def show_feedback_banner?
    return false unless current_user.employee?

    current_user.dismissed_notice?(FEEDBACK_BANNER_NOTICE) == false
  end

  sig { params(pull_request: PullRequest).returns(T.nilable(String)) }
  def findings_models_url(pull_request)
    PullRequests::Copilot::ApplyChangesHelper.models_url(
      repository: current_repository,
      pull_request: pull_request,
      user: current_user,
      helpers: helpers,
    )
  end

  sig { params(findings: T::Array[T::Hash[String, T.untyped]], pull_request: PullRequest).void }
  def enrich_findings_with_source_author(findings, pull_request)
    review_comment_ids = T.let(Set.new, T::Set[String])
    timeline_comment_ids = T.let(Set.new, T::Set[String])

    findings.each do |finding|
      refs = finding["sourceReferences"]
      next unless refs.is_a?(Array)

      refs.each do |ref|
        next unless ref.is_a?(Hash)

        entity_id = ref["entityId"].to_s
        next if entity_id.blank?

        case ref["source"]
        when "pr_review_comment", "ccr_review_comment"
          review_comment_ids.add(entity_id)
        when "pr_timeline_comment"
          timeline_comment_ids.add(entity_id)
        end
      end
    end

    return if review_comment_ids.empty? && timeline_comment_ids.empty?

    author_by_entity_id = T.let({}, T::Hash[String, User])

    if review_comment_ids.any?
      pull_request.review_comments.where(id: review_comment_ids.to_a).includes(:user).each do |comment| # domain-isolation-query-violation:ignore:packages/pull_requests (SELECT)
        user = comment.user
        author_by_entity_id[comment.id.to_s] = user if user&.bot?
      end
    end

    if timeline_comment_ids.any?
      T.must(pull_request.issue).comments.where(id: timeline_comment_ids.to_a).includes(:user).each do |comment| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        user = comment.user
        author_by_entity_id[comment.id.to_s] = user if user&.bot?
      end
    end

    return if author_by_entity_id.empty?

    findings.each do |finding|
      refs = finding["sourceReferences"]
      next unless refs.is_a?(Array)

      refs.each do |ref|
        next unless ref.is_a?(Hash)

        entity_id = ref["entityId"].to_s
        next if entity_id.blank?
        next unless COMMENT_SOURCE_TYPES.include?(ref["source"])

        author = author_by_entity_id[entity_id]
        if author
          ref["authorLogin"] = author.display_login
          ref["authorAvatarUrl"] = author.primary_avatar_url
          ref["authorIsBot"] = author.bot?
        end
      end
    end
  end

  sig { params(findings: T::Array[T::Hash[String, T.untyped]], pull_request: PullRequest).void }
  def enrich_findings_with_comment_previews(findings, pull_request)
    review_comment_ids = T.let(Set.new, T::Set[String])
    timeline_comment_ids = T.let(Set.new, T::Set[String])

    findings.each do |finding|
      refs = finding["sourceReferences"]
      next unless refs.is_a?(Array)

      refs.each do |ref|
        next unless ref.is_a?(Hash)

        entity_id = ref["entityId"].to_s
        next if entity_id.blank?

        case ref["source"]
        when "ccr_review_comment", "pr_review_comment"
          review_comment_ids.add(entity_id)
        when "pr_timeline_comment"
          timeline_comment_ids.add(entity_id)
        end
      end
    end

    return if review_comment_ids.empty? && timeline_comment_ids.empty?

    review_comments_by_id = fetch_review_comments_by_id(pull_request, review_comment_ids)
    timeline_comments_by_id = fetch_timeline_comments_by_id(pull_request, timeline_comment_ids)

    findings.each do |finding|
      refs = finding["sourceReferences"]
      next unless refs.is_a?(Array)

      previews = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

      refs.each do |ref|
        next unless ref.is_a?(Hash)

        entity_id = ref["entityId"].to_s
        next if entity_id.blank?

        preview = case ref["source"]
        when "ccr_review_comment"
          build_ccr_preview(review_comments_by_id[entity_id], pull_request)
        when "pr_review_comment"
          build_review_comment_preview(review_comments_by_id[entity_id], pull_request)
        when "pr_timeline_comment"
          build_timeline_comment_preview(timeline_comments_by_id[entity_id], pull_request)
        end

        previews << preview if preview
      end

      finding["commentPreviews"] = previews if previews.any?
    end
  end

  sig { params(pull_request: PullRequest, ids: T::Set[String]).returns(T::Hash[String, PullRequestReviewComment]) }
  def fetch_review_comments_by_id(pull_request, ids)
    return {} if ids.empty?

    comments = pull_request.review_comments
      .where(id: ids.to_a)
      .includes(:user, :pull_request_review, :automated_review_comment) # domain-isolation-query-violation:ignore:packages/pull_requests (SELECT)
      .to_a

    result = T.let({}, T::Hash[String, PullRequestReviewComment])
    comments.each { |c| result[c.id.to_s] = c }
    result
  end

  sig { params(pull_request: PullRequest, ids: T::Set[String]).returns(T::Hash[String, IssueComment]) }
  def fetch_timeline_comments_by_id(pull_request, ids)
    return {} if ids.empty?

    comments = T.must(pull_request.issue).comments
      .where(id: ids.to_a)
      .includes(:user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      .to_a

    result = T.let({}, T::Hash[String, IssueComment])
    comments.each { |c| result[c.id.to_s] = c }
    result
  end

  sig do
    params(
      comment: T.nilable(PullRequestReviewComment),
      pull_request: PullRequest,
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def build_ccr_preview(comment, pull_request)
    return nil unless comment

    review_variant_type = PullRequests::PageData::ThreadComments::Loader::CommentReviewVariantType.try_deserialize(
      comment.pull_request_review&.variant_type
    )
    return nil unless review_variant_type == PullRequests::PageData::ThreadComments::Loader::CommentReviewVariantType::Automated

    automated_review_comment = comment.automated_review_comment
    return nil unless automated_review_comment&.source_copilot?

    build_comment_preview_payload(comment, pull_request, automated_review_comment)
  end

  sig do
    params(
      comment: T.nilable(PullRequestReviewComment),
      pull_request: PullRequest,
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def build_review_comment_preview(comment, pull_request)
    return nil unless comment

    author = comment.user || User.ghost

    {
      author: {
        login: author.display_login,
        avatarUrl: author.primary_avatar_url,
        isBot: author.bot?,
      },
      bodyHTML: GitHub::Goomba::MarkdownPipeline.to_html(comment.body.to_s),
      url: comment.url,
      createdAt: comment.created_at&.iso8601,
      diffHunk: T.unsafe(comment).diff_hunk,
      commentDatabaseId: comment.id,
      basePath: pull_request.path_uri.to_s,
    }
  end

  sig do
    params(
      comment: T.nilable(IssueComment),
      pull_request: PullRequest,
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def build_timeline_comment_preview(comment, pull_request)
    return nil unless comment

    author = comment.user || User.ghost

    {
      author: {
        login: author.display_login,
        avatarUrl: author.primary_avatar_url,
        isBot: author.bot?,
      },
      bodyHTML: GitHub::Goomba::MarkdownPipeline.to_html(comment.body.to_s),
      url: T.unsafe(comment).url,
      createdAt: comment.created_at&.iso8601,
      commentDatabaseId: comment.id,
      basePath: pull_request.path_uri.to_s,
    }
  end

  sig do
    params(
      comment: PullRequestReviewComment,
      pull_request: PullRequest,
      automated_review_comment: AutomatedReviewComment,
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def build_comment_preview_payload(comment, pull_request, automated_review_comment)
    author = comment.user || User.ghost

    {
      author: {
        login: author.display_login,
        avatarUrl: author.primary_avatar_url,
        isBot: author.bot?,
      },
      title: automated_review_comment.title,
      bodyHTML: GitHub::Goomba::MarkdownPipeline.to_html(automated_review_comment.message),
      severity: automated_review_comment.display_severity,
      source: automated_review_comment.source.delete_prefix("source_"),
      url: comment.url,
      createdAt: comment.created_at&.iso8601,
      diffHunk: T.unsafe(comment).diff_hunk,
      commentDatabaseId: comment.id,
      basePath: pull_request.path_uri.to_s,
      suggestion: build_suggestion_payload(automated_review_comment),
    }
  end

  sig { params(automated_review_comment: AutomatedReviewComment).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def build_suggestion_payload(automated_review_comment)
    suggestion_state = automated_review_comment.suggestion_state
    formatted_state = suggestion_state.delete_prefix("suggestion_state_")

    if suggestion_state.in?(%w[suggestion_state_no_suggestion suggestion_state_pending suggestion_state_error])
      return nil
    end

    begin
      diff_entries_payload = automated_review_comment.suggestion&.diff_entries_payload
    rescue ::ReviewComments::Suggestion::ParseError => e
      Failbot.report!(e)
      return nil
    end

    return nil if diff_entries_payload.blank?

    {
      diffEntries: diff_entries_payload,
      state: formatted_state,
    }
  end
end
