# typed: true
# frozen_string_literal: true

module DependencyReview::ManifestLimitHelper
  DEPENDENCY_REVIEW_MANIFEST_LIMIT = 45.freeze

  def self.diff_too_large?(file_list_view)
    exceeds_manifest_limit?(diffs: file_list_view.diffs, repository: file_list_view.repository)
  end

  sig do
    params(
      diffs: GitHub::Diff,
      repository: T.nilable(T.any(Repository, Gist, GitHub::Unsullied::Wiki)),
    ).returns(T::Boolean)
  end
  def self.exceeds_manifest_limit?(diffs:, repository:)
    return false unless repository.try(:dependency_review_enabled?)
    # max_files is typically 300
    return true if diffs.deltas.count > diffs.max_files

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    modified_manifest_count = diffs.deltas
      .map { |d| d.new_file.path || d.old_file.path }
      .count { |path| !path.nil? && DependencyManifestFile.recognized_path?(path: path) }
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    elapsed_ms = ((end_time - start_time) * 1000).round
    GitHub.dogstats.distribution("dependency_graph.dependency_review.diff_too_large.time", elapsed_ms)

    modified_manifest_count > DEPENDENCY_REVIEW_MANIFEST_LIMIT
  end
end
