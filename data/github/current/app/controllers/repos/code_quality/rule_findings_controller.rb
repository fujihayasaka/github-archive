# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFindingsController < Repos::CodeQuality::BaseRepositoryController
  include CodeAnalysisControllerMethods
  include CodeQuality::FindingsSerializer
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action :check_code_quality_read
  before_action :ensure_feature_code_quality_enabled
  before_action :check_code_quality_write, only: [:update]
  before_action :try_parse_json_params, only: [:update]

  allow_verified_fetch only: [:update]
  sig { void }
  def index
    rule_id = params[:rule_id].to_s
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    file_path = nil
    if FeatureFlag.vexi.enabled?(:code_quality_backlog_rule_show, current_user, default: false)
      query = Search::Queries::CodeQualityFindingsQuery.new(params[:query].try(:to_str) || "")
      unless query.is_valid?
        return render json: {
          ruleFindings: [],
          prevCursor: nil,
          nextCursor: nil,
          openCount: 0,
          dismissedCount: 0,
        }, status: :ok
      end

      file_path = query.finding_path_filter
      finding_state = finding_state_from_query(query)

      response = GitHub::Turboquality.client.get_findings(Turboquality::Proto::GetFindingsRequest.new(
        repository_id: current_repository.id,
        rule_id:,
        page_size: DEFAULT_PER_PAGE,
        cursor: after_cursor || before_cursor,
        filter: Turboquality::Proto::RuleFindingsFilter.new(
          finding_state: finding_state,
          file_path: file_path,
        )
      ))
      # not_found is only returned if the rule_id is not found
      return render status: 404, json: { error: "Rule not found" } if response.error&.code == :not_found
      raise StandardError.new(response.error.to_s) if response.error

      # if there are no results, do not call `get_suggested_fixes` since it causes an invalid
      # argument error due to missing `finding_stable_ids`, use an empty fixes array instead
      suggested_fixes = []
      if !response.data.findings.empty?
        # extract finding ids from the response
        finding_stable_ids = response.data.findings.map(&:stable_id).uniq

        # fetch the suggested fixes for the findings
        suggested_fixes_response = GitHub::Turboquality.client.get_suggested_fixes(
          Turboquality::Proto::GetSuggestedFixesRequest.new(
            repository_id: current_repository.id,
            finding_stable_ids: finding_stable_ids,
          )
        )
        if suggested_fixes_response.error
          error = StandardError.new suggested_fixes_response.error.to_s
          Failbot.report(error)
        else
          suggested_fixes = suggested_fixes_response.data.fixes
        end
      end

      findings = serialized_findings(response.data.findings.to_a, suggested_fixes.to_a)
      payload = {
        ruleFindings: findings,
        prevCursor: response.data.prev_cursor,
        nextCursor: response.data.next_cursor,
        openCount: response.data.open_count,
        dismissedCount: response.data.dismissed_count,
      }
      render json: payload, status: :ok
    else
      finding_state = prepare_finding_state
      return finding_state if finding_state.is_a?(String)

      response = GitHub::Turboquality.client.results(Turboquality::Proto::ResultsRequest.new(
        repository_id: current_repository.id,
        rule_id:,
        page_size: DEFAULT_PER_PAGE,
        before_cursor:,
        after_cursor:,
        dismissal_state: finding_state,
        file_path:,
      ))
      # not_found is only returned if the rule_id is not found
      return render status: 404, json: { error: "Rule not found" } if response.error&.code == :not_found
      raise StandardError.new(response.error.to_s) if response.error

      # if there are no results, do not call `get_suggested_fixes` since it causes an invalid
      # argument error due to missing `finding_stable_ids`, use an empty fixes array instead
      suggested_fixes = []
      if !response.data.results.empty?
        # extract finding ids from the response
        finding_stable_ids = response.data.results.map(&:stable_id).uniq

        # fetch the suggested fixes for the findings
        suggested_fixes_response = GitHub::Turboquality.client.get_suggested_fixes(
          Turboquality::Proto::GetSuggestedFixesRequest.new(
            repository_id: current_repository.id,
            finding_stable_ids: finding_stable_ids,
          )
        )
        if suggested_fixes_response.error
          error = StandardError.new suggested_fixes_response.error.to_s
          Failbot.report(error)
        else
          suggested_fixes = suggested_fixes_response.data.fixes
        end
      end

      findings = serialized_findings_deprecated(response.data.results.to_a, suggested_fixes.to_a)
      payload = {
        ruleFindings: findings,
        prevCursor: response.data.prev_cursor,
        nextCursor: response.data.next_cursor,
        openCount: response.data.open_count,
        dismissedCount: response.data.dismissed_count,
      }
      render json: payload, status: :ok
    end
  end

  sig { void }
  def update
    return render_404 unless FeatureFlag.vexi.enabled?(:code_quality_backlog_rule_show, current_user, default: false)

    rule_id = params[:rule_id]
    state = params[:state]

    return render status: 422, json: { message: "Rule ID is required" } if rule_id.blank?
    return render status: 422, json: { message: "State is required" } if state.blank?
    return render status: 422, json: { message: "Findings must be an array" } unless params[:findings].is_a?(Array)
    return render status: 422, json: { message: "Findings cannot be empty" } if params[:findings].empty?

    findings = T.let([], T::Array[Turboquality::Proto::FindingIdentifier])
    params[:findings].each do |finding|
      return render status: 422, json: { message: "Each finding must be an object" } unless finding.respond_to?(:key?)

      stable_id = finding[:stable_id]
      file_path = finding[:file_path]

      return render status: 422, json: { message: "Each finding must have a stable_id" } if stable_id.blank?
      return render status: 422, json: { message: "Each finding must have a file_path" } if file_path.blank?

      findings << Turboquality::Proto::FindingIdentifier.new(
        stable_id: stable_id.to_s,
        file_path: file_path.to_s,
      )
    end

    state = GitHub::Turboquality.to_dismissal_state(state)
    if state.nil? || state == Turboquality::Proto::DismissalState::DISMISSAL_STATE_UNKNOWN
      return render status: 422, json: { message: "Invalid state: #{state}" }
    end

    response = GitHub::Turboquality.client.update_dismissal(Turboquality::Proto::UpdateDismissalRequest.new(
      repository_id: current_repository.id,
      rule_id:,
      state:,
      findings:,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    render status: 200, json: {}
  end

  private

  sig { params(findings: T::Array[Turboquality::Proto::Result], suggested_fixes: T::Array[Turboquality::Proto::SuggestedFix]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_findings_deprecated(findings, suggested_fixes)
    sha = current_repository.heads.find(current_repository.default_branch.b).sha
    blob_paths = findings.map { |finding| T.must(finding.location).file_path }.uniq
    blobs = blobs(
      commit_oid: sha,
      blob_paths:)
    suggested_fixes = suggested_fixes.index_by(&:finding_stable_id)
    highlighted_diff = SyntaxHighlightedDiff.new(current_repository)

    findings.filter_map do |finding|
      location = T.must(finding.location)
      start_line = location.start_line
      end_line = location.end_line.zero? ? location.start_line : location.end_line

      blob = blobs[location.file_path]

      suggested_fix = suggested_fixes[finding.stable_id]

      serialize_finding_deprecated(location.file_path, blob, start_line, end_line, location.start_column, location.end_column, finding.stable_id, suggested_fix, highlighted_diff)
    end
  end

  sig do
    params(
      file_path: String,
      blob: T.nilable(TreeEntry),
      start_line: Integer,
      end_line: Integer,
      start_column: Integer,
      end_column: Integer,
      stable_id: String,
      suggested_fix: T.nilable(Turboquality::Proto::SuggestedFix),
      highlighted_diff: SyntaxHighlightedDiff,
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def serialize_finding_deprecated(file_path, blob, start_line, end_line, start_column, end_column, stable_id, suggested_fix, highlighted_diff)
    # We select the lines of code surrounding the finding
    # to make sure the user has enough context.
    context_offset = 3
    context_start_line = [start_line - context_offset - 1, 0].max # - 1 because colorized_lines is 0-indexed

    lines = if blob.nil?
      []
    else
      context_end_line = end_line + context_offset < blob.colorized_lines.size ? end_line + context_offset : blob.colorized_lines.size
      blob.colorized_lines[context_start_line...context_end_line].to_a # excludes the context_end_line
    end

    result = {
      stableId: stable_id,
      filePath: file_path,
      startLine: start_line,
      endLine: end_line,
      startColumn: start_column,
      endColumn: end_column,
      snippetStartLine: context_start_line + 1,
      codeSnippetLines: lines,
    }

    if !suggested_fix.nil?
      result[:suggestedFix] = serialize_suggested_fix(suggested_fix, highlighted_diff)
    end

    result
  end

  sig { params(findings: T::Array[Turboquality::Proto::Finding], suggested_fixes: T::Array[Turboquality::Proto::SuggestedFix]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_findings(findings, suggested_fixes)
    sha = current_repository.heads.find(current_repository.default_branch.b).sha
    blob_paths = findings.map { |finding| T.must(finding.location).file_path }.uniq
    blobs = blobs(
      commit_oid: sha,
      blob_paths:)
    suggested_fixes = suggested_fixes.index_by(&:finding_stable_id)
    highlighted_diff = SyntaxHighlightedDiff.new(current_repository)

    findings.filter_map do |finding|
      finding_state = finding.finding_state
      finding_state = Turboquality::Proto::FindingState.lookup(finding_state) if finding_state.is_a?(Integer)
      finding_state = finding_state.to_s.downcase.delete_prefix("finding_state_")
      location = T.must(finding.location)
      start_line = location.start_line
      end_line = location.end_line.zero? ? location.start_line : location.end_line

      blob = blobs[location.file_path]

      suggested_fix = suggested_fixes[finding.stable_id]

      serialize_finding(location.file_path, blob, start_line, end_line, location.start_column, location.end_column, finding.stable_id, suggested_fix, highlighted_diff, finding_state)
    end
  end

  sig do
    params(
      file_path: String,
      blob: T.nilable(TreeEntry),
      start_line: Integer,
      end_line: Integer,
      start_column: Integer,
      end_column: Integer,
      stable_id: String,
      suggested_fix: T.nilable(Turboquality::Proto::SuggestedFix),
      highlighted_diff: SyntaxHighlightedDiff,
      finding_state: String,
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def serialize_finding(file_path, blob, start_line, end_line, start_column, end_column, stable_id, suggested_fix, highlighted_diff, finding_state)
    # We select the lines of code surrounding the finding
    # to make sure the user has enough context.
    context_offset = 3
    context_start_line = [start_line - context_offset - 1, 0].max # - 1 because colorized_lines is 0-indexed

    lines = if blob.nil?
      []
    else
      context_end_line = end_line + context_offset < blob.colorized_lines.size ? end_line + context_offset : blob.colorized_lines.size
      blob.colorized_lines[context_start_line...context_end_line].to_a # excludes the context_end_line
    end

    result = {
      stableId: stable_id,
      filePath: file_path,
      startLine: start_line,
      endLine: end_line,
      startColumn: start_column,
      endColumn: end_column,
      snippetStartLine: context_start_line + 1,
      codeSnippetLines: lines,
      findingState: finding_state,
    }

    if !suggested_fix.nil?
      result[:suggestedFix] = serialize_suggested_fix(suggested_fix, highlighted_diff)
    end

    result
  end

  sig { params(suggested_fix: Turboquality::Proto::SuggestedFix, highlighted_diff: SyntaxHighlightedDiff).returns(T::Hash[Symbol, T.untyped]) }
  def serialize_suggested_fix(suggested_fix, highlighted_diff)
    files = suggested_fix.files.map do |file|
      serialize_suggested_fix_file(
        diff_content: file.diff_content,
        file_path: file.file_path,
        highlighted_diff: highlighted_diff,
        include_raw_diff: false
      )
    end

    {
      state: suggested_fix.state.to_s.downcase.delete_prefix("suggested_fix_state_"),
      description: suggested_fix.description,
      files:
    }
  end

  sig { returns(T.any(T.nilable(Integer), String)) }
  def prepare_finding_state
    finding_state = params[:state]
    return Turboquality::Proto::DismissalState::DISMISSAL_STATE_OPEN if finding_state.nil?

    finding_state = GitHub::Turboquality.to_dismissal_state(finding_state)
    if finding_state.nil? || finding_state == Turboquality::Proto::DismissalState::DISMISSAL_STATE_UNKNOWN
      return render status: 422, json: { error: "Invalid state parameter" }
    end

    finding_state
  end

  sig { params(query: Search::Queries::CodeQualityFindingsQuery).returns(T.nilable(Integer)) }
  def finding_state_from_query(query)
    states = query.finding_state_filter
    return Turboquality::Proto::FindingState::FINDING_STATE_OPEN if states.empty?

    # Turboquality returns all findings if open and dismissed states are provided together.
    return nil if states.include?(Turboquality::Proto::FindingState::FINDING_STATE_OPEN) &&
      states.include?(Turboquality::Proto::FindingState::FINDING_STATE_DISMISSED)

    T.must(states.first)
  end
end
