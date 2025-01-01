# typed: strict
# frozen_string_literal: true

class PullRequests::Copilot::CompareTreesDiffCreator
  extend T::Sig

  MAX_FULL_FILES_PER_SIDE = 25

  sig do
    params(
      base_repo: Repository,
      head_repo: Repository,
      base_revision: T.untyped,
      head_revision: T.untyped,
      paths: T.untyped,
      context_lines: T.untyped
    ).returns({ diff_hunks: T.untyped })
  end
  def self.call(base_repo:, head_repo:, base_revision:, head_revision:, paths: nil, context_lines: nil)
    new(
      base_repo: base_repo,
      head_repo: head_repo,
      base_revision: base_revision,
      head_revision: head_revision,
      paths: paths,
      context_lines: context_lines
    ).call
  end

  sig do
    params(
      base_repo: Repository,
      head_repo: Repository,
      base_revision: T.untyped,
      head_revision: T.untyped,
      paths: T.untyped,
      context_lines: T.untyped
    ).void
  end
  def initialize(base_repo:, head_repo:, base_revision:, head_revision:, paths: nil, context_lines: nil)
    @base_repo = base_repo
    @head_repo = head_repo
    @base_revision = base_revision
    @head_revision = head_revision
    @paths = paths
    @context_lines = context_lines
  end

  sig { returns({ diff_hunks: T.untyped }) }
  def call
    { diff_hunks: diff_hunks }
  end

  sig { returns T::Array[T::Hash[T.untyped, T.untyped]] }
  def diff_hunks_without_line_numbers
    hunks.map do |dh|
      {
        change_reference: PullRequests::Copilot::Prompt::DiffHunkEncoder.encode(dh),
        header_context: dh.hunk_context&.to_str,
        diff: dh.diff_text_without_line_numbers.to_str,
        file_path: dh.file_path,
        diff_lines: dh.entry_line_attributes
      }
    end
  end

  sig { returns T::Array[T::Hash[String, T.untyped]] }
  def head_file_contents
    file_contents(head_repo, right_blobs)
  end

  sig { returns T::Array[T::Hash[String, T.untyped]] }
  def base_file_contents
    file_contents(base_repo, left_blobs)
  end

  private

  sig { returns Repository }
  attr_reader :base_repo, :head_repo

  sig { returns T.untyped }
  attr_reader :base_revision, :head_revision

  sig { returns T.untyped }
  attr_reader :paths

  sig { returns T.untyped }
  attr_reader :context_lines

  sig { returns T::Array[T::Hash[T.untyped, T.untyped]] }
  def diff_hunks
    hunks.map do |dh|
      {
        change_reference: PullRequests::Copilot::Prompt::DiffHunkEncoder.encode(dh),
        header_context: dh.hunk_context&.to_str,
        diff: dh.diff_text.to_str,
        file_path: dh.file_path,
        diff_lines: dh.entry_line_attributes
      }
    end
  end

  sig { returns Repositories::IRepository }
  def target
    if base_repo.fork?
      base_repo.parent || base_repo
    else
      base_repo
    end
  end

  sig { returns T.nilable(Users::IUser) }
  def owner
    target.owner
  end

  sig { returns T.nilable(T::Array[T.nilable(String)]) }
  def copilot_content_exclusion_rules
    owner = self.owner
    if owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(owner)
      content_exclusion_rules_for_repo = Copilot::ContentExclusion.rules_for_repo(target)
      copilot_content_exclusion_paths = content_exclusion_rules_for_repo.flat_map { |_config, rules| rules.collect(&:patterns) }.flatten.uniq
      copilot_content_exclusion_paths.map { |path| path[0] == "/" ? path[1..-1] : path }
    end
  end

  sig { returns T::Array[GitHub::Diff::Entry] }
  def filtered_diffs
    PullRequests::Copilot::DiffsFilter.new(diffs: comparison.diffs, copilot_content_exclusion: copilot_content_exclusion_rules).to_a
  end

  sig { params(repo: Repository, blobs: T::Hash[String, String]).returns T::Array[T::Hash[String, T.untyped]] }
  def file_contents(repo, blobs)
    file_contents = repo.rpc.read_blobs(blobs.keys)
    file_contents.map do |file|
      path = blobs[file["oid"]]
      {
        "path": path,
        "content": file["data"]
      }
    end
  rescue GitRPC::Error => e
    Failbot.report(e)
    []
  end

  sig { returns T::Hash[String, String] }
  def right_blobs
    unique_files = filtered_diffs.uniq { |diff| diff.b_path }.first(MAX_FULL_FILES_PER_SIDE)
    unique_files.each_with_object({}) { |diff, hash| hash[diff.b_blob] = diff.b_path }.compact
  end

  sig { returns T::Hash[String, String] }
  def left_blobs
    unique_files = filtered_diffs.uniq { |diff| diff.a_path }.first(MAX_FULL_FILES_PER_SIDE)
    unique_files.each_with_object({}) { |diff, hash| hash[diff.a_blob] = diff.a_path }.compact
  end

  sig { returns T::Array[PullRequests::Copilot::DiffHunk] }
  def hunks
    PullRequests::Copilot::DiffHunk.diffs_to_hunks(filtered_diffs)
  end

  sig { returns GitHub::Comparison }
  def comparison
    result = GitHub::Comparison.build(base_repo: base_repo, head_repo: head_repo, base_revision: base_revision, head_revision: head_revision)
    result.set_diff_options(diff_options)
    result
  end

  sig { returns T::Hash[T.untyped, T.untyped] }
  def diff_options
    result = { ignore_whitespace: true }
    result[:paths] = paths if paths.present?
    if context_lines.present?
      lines = context_lines.map { |cl| ["#{cl.path}", [cl.start..cl.end]] }.to_h
      result[:context_lines] = lines
    end
    result
  end
end
