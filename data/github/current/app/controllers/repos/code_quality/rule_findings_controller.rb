# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFindingsController < Repos::CodeQuality::BaseRepositoryController
  include CodeAnalysisControllerMethods
  include CodeQuality::FindingsSerializer

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

  sig { void }
  def index
    rule_id = params[:rule_id].to_s
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    finding_state = prepare_finding_state
    return finding_state if finding_state.is_a?(String)

    response = GitHub::Turboquality.client.results(Turboquality::Proto::ResultsRequest.new(
      repository_id: current_repository.id,
      rule_id:,
      page_size: DEFAULT_PER_PAGE,
      before_cursor:,
      after_cursor:,
      dismissal_state: finding_state,
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

    findings = serialized_findings(response.data.results.to_a, suggested_fixes.to_a)
    payload = {
      ruleFindings: findings,
      prevCursor: response.data.prev_cursor,
      nextCursor: response.data.next_cursor,
      openCount: response.data.open_count,
      dismissedCount: response.data.dismissed_count,
    }
    render json: payload, status: :ok
  end

  private

  sig { params(findings: T::Array[Turboquality::Proto::Result], suggested_fixes: T::Array[Turboquality::Proto::SuggestedFix]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_findings(findings, suggested_fixes)
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

      serialize_finding(location.file_path, blob, start_line, end_line, location.start_column, location.end_column, finding.stable_id, suggested_fix, highlighted_diff)
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
  def serialize_finding(file_path, blob, start_line, end_line, start_column, end_column, stable_id, suggested_fix, highlighted_diff)
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
end
