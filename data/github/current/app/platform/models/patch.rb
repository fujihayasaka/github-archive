# typed: true
# frozen_string_literal: true

class Platform::Models::Patch
  include ActionView::Helpers::TagHelper
  include DiffLineChangeMarker
  include GitHub::Relay::GlobalIdentification

  LARGE_DIFF_LINES = 500

  attr_reader :pull_request

  # diff           - An instance of Platform::Models::Diff to which this patch belongs
  # delta_or_entry - An instance of either a GitRPC::Diff::Delta or GitHub::Diff::Entry which this
  #                  patch wraps
  def initialize(diff, delta_or_entry, pull_request: nil)
    @diff    = diff
    @subject = delta_or_entry
    @pull_request = pull_request
  end

  def self.load_from_global_id(id)
    parts = id.split(":", 6)
    raise Platform::Errors::InvalidValue.new("Incorrect number of parts") unless parts.length == 6
    repo_id, base_repo_id, head_repo_id, before_oid, after_oid, path = parts

    Platform::Loaders::ActiveRecord.load(::Repository, repo_id.to_i).then do |repo|
      next unless repo

      Platform::Helpers::Diff.for(
        head_repo_id: head_repo_id.to_i,
        base_repo_id: base_repo_id.to_i,
        start_ref_or_oid: before_oid,
        end_ref_or_oid: after_oid,
        use_summary: false,
        compare_repo: repo,
        paths: [path]
      ).then do |diff|
        unless (entry = diff.entries.find { |entry| entry.path == path })
          raise Platform::Errors::NotFound.new("Could not resolve to a node with the given global id")
        end

        new(diff, entry)
      end
    end
  end

  # Manually generate the ID for enterprise
  # GitHub::Relay::GlobalIdentification requires this ID
  # since patch does not have a database ID
  def id
    [
      diff.repo.id.to_i,
      diff.base_repo.id.to_i,
      diff.head_repo_id.to_i,
      before_oid,
      after_oid,
      path
    ].join(":")
  end

  delegate :additions, :binary?, :too_big?, :changes, :deletions, :similarity, :submodule?, :unicode_text, to: :subject

  attr_reader :diff

  def is_large_diff?
    !delta? && (too_big? || subject.line_count > LARGE_DIFF_LINES)
  end

  def lfs_pointer?
    !delta? && Media::Pointer.parse_diff(subject.text).any?
  end

  def new_tree_entry
    return nil if subject.deleted?
    if delta?
      ::TreeEntry.new(diff.repo, info_from_tree_node(subject.new_file))
    else
      ::TreeEntry.new(diff.repo, new_info_from_diff_entry)
    end
  end

  def old_tree_entry
    return nil if subject.added?
    if delta?
      ::TreeEntry.new(diff.repo, info_from_tree_node(subject.old_file))
    else
      ::TreeEntry.new(diff.repo, old_info_from_diff_entry)
    end
  end

  # Path Ownership for this patch
  #
  # Returns PathOwnership object for this patch
  def path_ownership
    Platform::Models::PathOwnership.new(codeowners: diff.codeowners, diff: diff, path: path)
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

  def contents_url
    sha, path = diff_sha_and_path(subject)
    repo = diff.repo.name_with_owner_for_api

    url = "#{GitHub.api_url}/repos/#{repo}/contents/#{path}?ref=#{sha}"
    Addressable::URI.encode(url)
  end

  def async_diff_lines(syntax_highlighted_diffs_enabled:, injected_context_lines:)
    return Promise.resolve([]) if delta?

    diff_lines_subject = if injected_context_lines.present?
      entry_for_context_lines(injected_context_lines)
    else
      subject
    end

    repo = diff.repo
    async_warm_syntax_highlighted_diff = if syntax_highlighted_diffs_enabled
      Platform::Loaders::WarmSyntaxHighlightedDiffCache.load(repo, nil, diff_lines_subject)
    else
      Promise.resolve(nil)
    end

    async_warm_syntax_highlighted_diff.then do
      lines = SyntaxHighlightedDiff.new(repo).colorized_lines(diff_lines_subject)
      if lines
        lines.each(&:freeze)
        lines.freeze
      end

      diff_lines_subject.enumerator.map do |line|
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
          diff: diff,
          path: path
        }
      end
    end
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
    if delta?
      subject.old_file.oid
    else
      subject.a_sha
    end
  end

  def after_oid
    if delta?
      subject.new_file.oid
    else
      subject.b_sha
    end
  end

  def truncated_reason
    subject.truncated_reason
  end

  private

  attr_reader :subject

  def blob_or_raw_url(type:)
    return nil if subject.submodule?

    sha, path = diff_sha_and_path(subject)
    repo = diff.repo.name_with_display_owner

    url = "#{GitHub.url}/#{repo}/#{type}/#{sha}/#{path}"
    Addressable::URI.encode(url)
  end

  def diff_sha_and_path(subject)
    if delta?
      a = subject.old_file
      b = subject.new_file

      subject.deleted? ? [a.oid, a.path] : [b.oid, b.path]
    else
      subject.deleted? ? [subject.a_sha, subject.a_path] : [subject.b_sha, subject.b_path]
    end
  end

  def delta?
    subject.is_a?(GitRPC::Diff::Delta)
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
      rpc: diff.repo.rpc,
      repo: diff.repo,
    )

    # Breaking immediately to stop at the first entry.
    GitHub::Diff::Parser.new(injector.expanded_diff).each { |entry| break entry }
  end
end
