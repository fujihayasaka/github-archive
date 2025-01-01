# typed: true
# frozen_string_literal: true

class Platform::Models::Diff
  include GitHub::Relay::GlobalIdentification
  def initialize(head_repo_id:, base_repo:, start_ref_or_oid:, end_ref_or_oid:, base_commit_oid: nil,
                 algorithm: GitRPC::Diff::ALGORITHM_DEFAULT, use_summary:, timeout: nil, compare_repo:, context_lines: {}, paths: [],
                 pull_request: nil)
    @base_repo = base_repo
    @head_repo_id = head_repo_id
    @algorithm = algorithm

    @diff = GitHub::Diff.new(compare_repo, start_ref_or_oid, end_ref_or_oid, base_sha: @base_commit_oid,
                                                                             use_summary: @use_summary.nil? ? use_summary : @use_summary,
                                                                             timeout: @timeout,
                                                                             context_lines: context_lines,
                                                                             paths: paths,
                                                                             ignore_whitespace: ignore_whitespace?
                                                                            )
    @pull_request = pull_request
  end

  attr_reader :base_repo, :algorithm, :diff, :head_repo_id, :pull_request

  delegate :entries, :deltas, :changed_files, :additions, :deletions, :changes, :repo, to: :diff

  def platform_type_name
    "Diff"
  end

  def global_id
    id_array = [
      base_repo.id,
      diff.parsed_sha1,
      @head_repo_id,
      diff.parsed_sha2,
      diff.base_sha,
      algorithm,
    ]

    id_array.compact.join(":")
  end

  # Codeowners for the entries (aka "patches") in this diff, based on the base repo and base sha
  #
  # Returns Repository::Codeowners instance
  def codeowners
    @codeowners ||= Repository::Codeowners.new(base_repo, ref: diff.base_sha).tap do |codeowners|
      codeowners.paths = diff.entries.map(&:path) if codeowners.file
    end
  end

  def async_pr_comparison
    return Promise.resolve(nil) unless pull_request
    @pr_comparison ||= pull_request.async_pull_comparison(start_oid: diff.parsed_sha1, end_oid: diff.parsed_sha2, base_oid: pull_request.base_sha)
  end

  def async_positioned_threads_for(viewer:, path:, position:)
    async_pr_comparison.then do |comparison|
      next unless comparison
      thread_positioner = comparison.thread_positioner(viewer: viewer)

      thread_positioner.positioned_threads.path(path).position(position)
    end
  end

  private

  def ignore_whitespace?
    algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
  end
end
