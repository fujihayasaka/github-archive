# typed: true
# frozen_string_literal: true

require "diff-analysis"

class WorkspaceEditor::DiffAnalysisClient
  include Commit::ReactPayloadDataDependency

  def self.analyze(pull:, current_user:, categorize: false, detect_patch_risk: false)
    new(pull_request: pull, current_user:, categorize: categorize, detect_patch_risk: detect_patch_risk).analyze_diff
  end

  def initialize(pull_request:, current_user:, categorize: false, detect_patch_risk: false)
    @pull_request = pull_request
    @current_user = current_user
    @categorize = categorize
    @detect_patch_risk = detect_patch_risk
  end

  attr_reader :pull_request, :current_user, :categorize, :detect_patch_risk

  def analyze_diff
    response = client.analyze_diff(analyze_request)
    response.data.to_h
  end

  private

  def analyze_request
    DiffAnalysis::V1::AnalyzeDiffRequest.new(
      files: file_entries,
      categorize: categorize,
      detect_patch_risk: detect_patch_risk,
    )
  end

  def file_entries
    diffs, new_tree_entries, old_tree_entries = get_prefilled_tree_entries(file_list_view)

    diffs.map do |diff|
      current_diff = diff.diff
      new_diff = new_tree_entries.find { |entry| entry.path == current_diff.b_path }
      old_diff = old_tree_entries.find { |entry| entry.path == current_diff.a_path }

      DiffAnalysis::V1::FileDiff.new(
        path: current_diff.path,
        left: encode_binary(old_diff&.data),
        right: encode_binary(new_diff&.data),
        change_type: diff_status(current_diff.status),
      )
    end
  end

  def encode_binary(data)
    return nil if data.nil?
    data.force_encoding(Encoding::BINARY)
  end

  def start_oid
    pull_request.merge_base
  end

  def end_oid
    pull_request.head_sha
  end

  def diff
    GitHub::Diff.new(pull_request.repository, start_oid, end_oid)
  end

  def file_list_view
    _, end_commit = pull_request.compare_repository.commits.find([start_oid, end_oid])
    ::Diff::FileListView.new(commit: end_commit, diffs: diff, current_user: current_user)
  end

  def diff_status(status)
    case status.upcase
    when "A" then DiffAnalysis::V1::ChangeType::ADDED
    when "M" then DiffAnalysis::V1::ChangeType::MODIFIED
    when "D" then DiffAnalysis::V1::ChangeType::REMOVED
    end
  end

  def client
    DiffAnalysis::V1::DiffAnalysisServiceClient.new(GitHub.diff_analysis_url)
  end
end
