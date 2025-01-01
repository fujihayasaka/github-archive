# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFindingsController < Repos::CodeQuality::BaseRepositoryController
  include ScanningControllerMethods

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

  before_action :check_code_scanning_read

  sig { void }
  def index
    rule_id = params[:rule_id].to_s
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    response = GitHub::Turboquality.client.results(Turboquality::Proto::ResultsRequest.new(
      repository_id: current_repository.id,
      rule_id:,
      page_size: DEFAULT_PER_PAGE,
      before_cursor:,
      after_cursor:,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    findings = serialized_findings(response.data.results.to_a)
    payload = {
      ruleFindings: findings,
      findingsCount: response.data.result_count,
      prevCursor: response.data.prev_cursor,
      nextCursor: response.data.next_cursor,
    }
    render json: payload, status: :ok
  end

  private

  sig { params(findings: T::Array[Turboquality::Proto::Result]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_findings(findings)
    sha = current_repository.heads.find(current_repository.default_branch.b).sha
    blob_paths = findings.map { |finding| T.must(finding.location).file_path }.uniq
    blobs = blobs(
      commit_oid: sha,
      blob_paths:)

    findings.filter_map do |finding|
      location = T.must(finding.location)
      start_line = location.start_line
      end_line = location.end_line.zero? ? location.start_line : location.end_line

      blob = blobs[location.file_path]

      serialize_finding(location.file_path, blob, start_line, end_line, location.start_column, location.end_column)
    end
  end

  sig do
    params(
      file_path: String,
      blob: T.nilable(TreeEntry),
      start_line: Integer,
      end_line: Integer,
      start_column: Integer,
      end_column: Integer
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def serialize_finding(file_path, blob, start_line, end_line, start_column, end_column)
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

    {
      filePath: file_path,
      startLine: start_line,
      endLine: end_line,
      startColumn: start_column,
      endColumn: end_column,
      snippetStartLine: context_start_line + 1,
      codeSnippetLines: lines,
    }
  end
end
