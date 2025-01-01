# typed: true
# frozen_string_literal: true

class Platform::Models::PullRequestDiffEntry
  include ActionView::Helpers::TagHelper
  include DiffLineChangeMarker
  include GitHub::Relay::GlobalIdentification

  include Scientist

  LARGE_DIFF_LINES = 500
  FULL_CONTEXT_LIMIT = 150.kilobytes

  delegate :additions, :binary?, :too_big?, :changes, :deletions, :similarity, :submodule?, :unicode_text, to: :subject

  attr_reader :pull_request, :pull_request_comparison

  # pull_request_comparison - An instance of PullRequestComparison to which this diff_entry belongs
  # diff_entry - An instance of a GitHub::Diff::Entry, which this model wraps
  def initialize(diff_entry:, pull_request_comparison:, pull_request:)
    @subject = diff_entry
    @pull_request_comparison = pull_request_comparison
    @pull_request = pull_request
  end

  def self.load_from_global_id(id)
    parts = id.split(":", 6)
    raise Platform::Errors::InvalidValue.new("Incorrect number of parts") if parts.length != 6

    pull_request_id, start_oid, end_oid, base_commit_oid, path, repository_id = parts

    Platform::Loaders::ActiveRecord.load(::PullRequest, pull_request_id.to_i).then do |pull_request|
      ::PullRequest::Comparison.async_find(
        pull: pull_request,
        start_commit_oid: start_oid,
        end_commit_oid: end_oid,
        base_commit_oid: base_commit_oid,
        use_summary: true
      ).then do |comparison|
        entry = comparison && comparison.diff.entries.find { |entry| entry.path == path }

        if !entry
          raise Platform::Errors::NotFound.new("Could not resolve PullRequestDiffEntry to a node with the given global relay id: #{id}")
        end

        new(diff_entry: entry, pull_request_comparison: comparison, pull_request: pull_request)
      end
    end
  end

  # Manually generate the ID for enterprise
  # GitHub::Relay::GlobalIdentification requires this ID
  # Since a PullRequestDiffEntry is not backed by a database record
  def id
    [
      pull_request.id,
      pull_request_comparison.start_commit.oid,
      pull_request_comparison.end_commit.oid,
      pull_request_comparison.base_commit.oid,
      path,
      pull_request_comparison.repository.id
    ].join(":")
  end

  def is_large?
    too_big? || subject.line_count > LARGE_DIFF_LINES
  end

  def lfs_pointer?
    Media::Pointer.parse_diff(subject.text).any?
  end

  def status
    status = subject.status_label.to_sym

    return :deleted if status == :removed

    status
  end

  def text
    GitHub::Encoding.try_guess_and_transcode(subject.text)
  end

  def blob_url
    blob_or_raw_url(type: "blob")
  end

  def raw_url
    blob_or_raw_url(type: "raw")
  end

  def path_digest
    Digest::SHA256.hexdigest(path)
  end

  def path
    diff_sha_and_path(subject)[1]
  end

  def oid
    diff_sha_and_path(subject)[0]
  end

  def before_oid
    subject.a_sha
  end

  def after_oid
    subject.b_sha
  end

  def truncated_reason
    subject.truncated_reason
  end

  def path_ownership
    Platform::Models::PathOwnership.new(
      codeowners: pull_request_comparison.codeowners,
      diff: pull_request_comparison.diff,
      path: path
    )
  end

  def new_tree_entry
    return nil if subject.deleted?

    ::TreeEntry.new(pull_request_comparison.diff.repo, new_info_from_diff_entry)
  end

  def old_tree_entry
    return nil if subject.added?

    ::TreeEntry.new(pull_request_comparison.diff.repo, old_info_from_diff_entry)
  end

  def contents_url
    sha, path = diff_sha_and_path(subject)
    repo = pull_request_comparison.diff.repo.name_with_owner_for_api

    url = "#{GitHub.api_url}/repos/#{repo}/contents/#{path}?ref=#{sha}"
    Addressable::URI.encode(url)
  end

  def async_diff_lines(injected_context_lines: nil)
    entry_info = injected_context_lines ? entry_for_context_lines(injected_context_lines) : subject
    async_warm_syntax_highlighted_diff = Platform::Loaders::WarmSyntaxHighlightedDiffCache.load(pull_request_comparison.diff.repo, nil, entry_info)
    set_injected_context_lines_on_comparison_diff(injected_context_lines)

    async_warm_syntax_highlighted_diff.then do
      lines = SyntaxHighlightedDiff.new(pull_request_comparison.diff.repo).colorized_lines(entry_info)
      if lines
        lines.each(&:freeze)
        lines.freeze
      end

      entry_info.enumerator.map do |line|
        if lines
          html = lines[line.position]
          related_html = line.related_line ? lines[line.related_line.position] : nil
          html = mark_intra_line_changes_html(line, html, related_html)
        else
          html = line.related_line ? mark_intra_line_changes(line) : line.text
        end

        html = h(html)
        html.chomp!
        html.gsub!("\r", "")
        html = "<br>" unless html.present?

        {
          type: line.type,
          blob_line_number: line.current,
          text: line.text,
          html: html,
          position: line.position,
          left: line.left == -1 ? nil : line.left,
          right: line.right == -1 ? nil : line.right,
          no_newline_at_end: line.nonewline?,
          pull_request: pull_request,
          pull_request_comparison: pull_request_comparison,
          diff: pull_request_comparison.diff,
          path: path
        }
      end
    end
  end

  def can_expand_full_context_lines?
    return false unless subject.can_inject_context? && can_expand_blob?

    subject_enumerator = subject.enumerator
    first_diff_line_number = subject_enumerator.first.current.to_i

    return true if first_diff_line_number > 0

    last_diff_line_number = subject_enumerator.to_a.last.current.to_i
    file_line_count = new_tree_entry.line_count.to_i

    last_diff_line_number < file_line_count
  end

  private

  attr_reader :subject

  def blob_or_raw_url(type:)
    return nil if subject.submodule?

    sha, path = diff_sha_and_path(subject)
    repo = pull_request_comparison.repo.name_with_display_owner

    url = "#{GitHub.url}/#{repo}/#{type}/#{sha}/#{path}"
    Addressable::URI.encode(url)
  end

  def diff_sha_and_path(subject)
    subject.deleted? ? [subject.a_sha, subject.a_path] : [subject.b_sha, subject.b_path]
  end

  def info_from_tree_node(node)
    { "path" => GitHub::Encoding.try_guess_and_transcode(node.path), "mode" => node.mode, "oid" => node.oid, "type" => "blob" }
  end

  def new_info_from_diff_entry
    { "path" => subject.b_path || "", "mode" => subject.b_mode, "oid" => subject.b_blob, "type" => "blob" }
  end

  def old_info_from_diff_entry
    { "path" => subject.a_path || "", "mode" => subject.a_mode, "oid" => subject.a_blob, "type" => "blob" }
  end

  def entry_for_context_lines(lines)
    context_lines = lines.map { |line| line.start..line.end }
    injector = GitHub::Diff::ContextInjector.new(
      diff_text: subject.to_diff_text,
      context_lines: { subject.path => context_lines },
      sha2: subject.b_sha,
      rpc: pull_request_comparison.diff.repo.rpc,
      repo: pull_request_comparison.diff.repo,
    )

    # Breaking immediately to stop at the first entry.
    GitHub::Diff::Parser.new(injector.expanded_diff).each { |entry| break entry }
  end

  def set_injected_context_lines_on_comparison_diff(injected_context_lines)
    return if !injected_context_lines

    # We must format the graphql argument injected_context_lines
    # into a thread positioner compliant context lines hash
    # e.g. {"utility.js"=>[0..7, 7..27], "README.md"=>[15..35]}
    pull_request_comparison.diff.context_lines = (pull_request_comparison.diff.context_lines || {}).merge({
      "#{path}" => injected_context_lines.map { |lines|  lines.start..lines.end }
    })
  end

  def can_expand_blob?
    new_tree_entry.size < FULL_CONTEXT_LIMIT && old_tree_entry.size < FULL_CONTEXT_LIMIT
  end
end
