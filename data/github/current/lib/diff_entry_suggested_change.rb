# typed: true
# frozen_string_literal: true

class DiffEntrySuggestedChange
  class Error < StandardError; end
  class UnprocessableError < Error; end
  # Data integrity errors that indicate a bug (corrupted refs, bad diff data).
  # Unlike UnprocessableError, these warrant investigation.
  class InvalidDataError < UnprocessableError; end
  class ConflictError < UnprocessableError; end
  class NotFoundError < Error; end
  class ForbiddenError < Error; end

  NEWLINE_REGEXP = Regexp.union(["\r\n", "\r", "\n"])

  attr_reader :pull_request
  attr_reader :tree_name
  attr_reader :repository
  attr_reader :diff_entries
  attr_reader :file_contents

  def initialize(repository:, diff_entries:, pull_request: nil, ref: nil)
    if pull_request.nil? && ref.nil?
      raise ArgumentError, "provide pull_request or ref"
    end

    @pull_request = pull_request
    @tree_name = pull_request ? pull_request.head_ref : ref.qualified_name
    @repository = repository
    @diff_entries = diff_entries
    @file_contents = {}
    @ref = ref
  end

  # Build file contents from diff entries. For each path, all deletion/addition lines from
  # every entry are merged into a single, position-sorted list and applied in one forward pass.
  sig { params(blobs: T.nilable(T::Hash[String, TreeEntry])).returns(T::Hash[String, String]) }
  def build_new_files(blobs: nil)
    # Group diff entries by path
    entries_by_path = diff_entries.group_by(&:path)

    entries_by_path.each_with_object({}) do |(path, entries), out|
      blob = if blobs.nil?
        blob_at_path(path)
      else
        unless blobs[path]
          GitHub.logger.warn("DiffEntrySuggestedChange: missing blob in provided blobs", **log_context, "gh.file_path": path)
          raise(NotFoundError.new("Missing blob for #{path}."))
        end
        blobs[path]
      end

      source_lines = blob.data.split(NEWLINE_REGEXP, -1)

      merged_diff_lines = create_sorted_diff_lines(entries)

      # Apply all lines in a single forward pass through the source
      source_lines = apply_merged_diff_lines(merged_diff_lines, source_lines)

      out[path] = source_lines.join(line_endings(blob))
    end
  end

  # Merges all deletion/addition lines from every entry into a single list sorted by
  # left-side (original) position. The sorted list can be applied in a single
  # forward pass through the source file, which naturally handles entries with
  # non-contiguous hunks (e.g., lines 1-10 and 200-205) without entry-level sorting.
  #
  # Raises UnprocessableError if any entries overlap on the same original line.
  sig { params(diff_entries: T::Array[GitHub::Diff::Entry]).returns(T::Array[GitHub::Diff::Line]) }
  def create_sorted_diff_lines(diff_entries)
    # Use left-side (original) coordinates for stable overlap detection.
    # For deletions, `line.left` is the original line being removed.
    # For additions, `line.left` is the insertion anchor (the original line
    # the new content is inserted after); if unavailable, we raise an error.
    all_touched_positions = diff_entries.flat_map do |entry|
      diff_lines = entry.basic_enumerator.filter_map do |line|
        if line.deletion? || line.addition?
          if line.left.nil?
            raise InvalidDataError.new(
              "Cannot apply suggestions that have no left position for a diff line " \
              "in #{entry.path.inspect}"
            )
          end

          line.left
        end
      end

      diff_lines.uniq
    end

    # Check for overlapping positions
    # We raise an error here because overlapping suggestions should have been prevented by the UI
    if all_touched_positions.length != all_touched_positions.uniq.length
      paths = diff_entries.map(&:path).compact.uniq
      raise ConflictError.new(
        "Cannot apply suggestions that modify the same line in #{paths.join(', ')}"
      )
    end

    # Merge all modification lines from all entries into a single list.
    # Since line.left is always set by the enumerator (it carries the last left-side
    # value through additions), we can sort all lines by their left-side position and
    # apply in a single forward pass. This correctly handles entries with non-contiguous
    # hunks (e.g., lines 1-10 and 200-205) without needing entry-level sorting.
    all_mod_lines = diff_entries.flat_map do |entry|
      entry.basic_enumerator.select { |line| line.deletion? || line.addition? }
    end

    # Sort by left-side position. Deletions before additions at the same position,
    # so we remove the original line before inserting replacements.
    all_mod_lines.sort_by! { |line| [line.left, line.deletion? ? 0 : 1, line.right || 0] }
  end

  def commit_change_for_user(author:, files: build_new_files, current_oid:, message: nil, co_author_note: nil, reflog_data: nil, sign: false)
    unless repository.pushable_by?(author, ref: tree_name)
      GitHub.logger.warn("DiffEntrySuggestedChange: permission denied", **log_context)
      raise ForbiddenError.new("You don't have permission to apply suggestions.")
    end

    if pull_request && !pull_request.open?
      GitHub.logger.warn("DiffEntrySuggestedChange: pull request not open", **log_context)
      raise UnprocessableError.new("Suggestion can only be applied to open pull requests.")
    end

    author_email = author.default_author_email(repository)
    if author_email && !author.author_emails.include?(author_email)
      GitHub.logger.warn("DiffEntrySuggestedChange: invalid email for web commit", **log_context)
      raise UnprocessableError.new("Invalid email for web commit.")
    end

    if ref.target_oid != current_oid
      GitHub.logger.warn("DiffEntrySuggestedChange: diff outdated", **log_context)
      raise UnprocessableError.new("Sorry, the diff is outdated.")
    end

    dco_signoff_enabled = pull_request ? pull_request.dco_signoff_enabled? : repository.dco_signoff_enabled?

    commit_body = begin
      arr = []
      arr << co_author_note
      arr << DcoSignoffHelper.dco_signoff_text(author) if dco_signoff_enabled
      arr.join("\n")
    end

    commit_message = begin
      default_title = String.new
      if files.length == 1
        default_title << "Update #{files.keys.first}".dup.force_encoding("UTF-8").scrub!
      else
        default_title << "Updating #{files.length} files"
      end

      title = (message.presence || default_title).strip

      parts = [title, commit_body]
      parts.reject(&:blank?).join("\n\n")
    end

    result = repository.commit_change_for_user(
      author:,
      author_email:,
      branch:,
      files:,
      message: commit_message,
      pull_request:,
      reflog_data:,
      sign:,
      ref:,
    )

    commit_oid, _branch, hook_error = result
    unless commit_oid
      GitHub.logger.warn("DiffEntrySuggestedChange: commit rejected by hook", **log_context)
      raise UnprocessableError.new(hook_error)
    end

    result
  end

  def branch
    return @branch if defined?(@branch)

    @branch = GitHub::RefShaPathExtractor.new(repository).call(tree_name).first
  end

  def ref
    @ref ||= repository.heads.find(tree_name)
  end

  private

  # Apply a sorted list of merged diff lines (deletions and additions only) to source lines.
  # Lines must be sorted by [left, type] where deletions come before additions at the same position.
  # Uses left-side (original) coordinates for stable positioning across entries.
  sig do
    params(
      sorted_diff_lines: T::Array[GitHub::Diff::Line],
      source_lines: T::Array[String]
    ).returns(T::Array[String])
  end
  def apply_merged_diff_lines(sorted_diff_lines, source_lines)
    result = []
    anchor_index = 0 # 0-based index into source_lines

    sorted_diff_lines.each do |line|
      # For deletions, anchor to just before the deleted line (left - 1) so we
      # copy all source lines preceding it.
      # For additions, anchor to left so we copy source lines up to and including
      # the anchor line.
      diff_line_anchor = line.deletion? ? line.left - 1 : line.left
      while anchor_index < diff_line_anchor
        result << source_lines[anchor_index]
        anchor_index += 1
      end

      if line.deletion?
        # Skip over the deleted source line
        anchor_index += 1
      elsif line.addition?
        # Insert the new line (strip the leading '+' diff prefix)
        result << line.text[1..-1]
      end
    end

    # Copy remaining source lines
    while anchor_index < source_lines.size
      result << source_lines[anchor_index]
      anchor_index += 1
    end

    result
  end

  def current_commit
    return @current_commit if defined?(@current_commit)

    commit_sha = repository.ref_to_sha(tree_name)
    if commit_sha.blank?
      GitHub.logger.warn("failed to resolve current commit: ref_to_sha returned blank",
        "code.namespace": self.class.name, "code.function": __method__)
    end

    @current_commit = commit_sha.presence && repository.commits.find(commit_sha)
    if @current_commit.nil? && commit_sha.present?
      GitHub.logger.warn("failed to resolve current commit: commits.find returned nil",
        "code.namespace": self.class.name, "code.function": __method__)
    end

    @current_commit
  rescue GitRPC::InvalidObject, GitRPC::BadObjectState => e
    GitHub.logger.error("failed to resolve current commit",
      exception: e, "code.namespace": self.class.name, "code.function": __method__)

    @current_commit = nil
  rescue GitRPC::ObjectMissing => e
    GitHub.logger.error("failed to resolve current commit",
      exception: e, "code.namespace": self.class.name, "code.function": __method__)

    @current_commit = nil

    # ref points to a missing object, aka repository corruption.
    #
    # it's conceivable that this could be raised mistakenly if we had a bad deploy or
    # an operational problem that caused GitRPC::ObjectMissing to be raised when the
    # objects did in fact exist.
    if ref = repository.refs.find(tree_name)
      raise InvalidDataError.new("ref #{ref.qualified_name} points at missing commit #{ref.target_oid}")
    end

    @current_commit
  end

  def blob_at_path(path)
    return @file_contents[path] if @file_contents.key?(path)

    if current_commit.nil?
      GitHub.logger.warn("DiffEntrySuggestedChange: head commit not found", **log_context)
      raise NotFoundError.new("Could not resolve the head commit for '#{tree_name}'. This diff may have been recently updated.")
    end

    blob = repository.blob(current_commit.tree_oid, path, { truncate: false, limit: 1.megabyte })
    if blob.blank?
      GitHub.logger.warn("DiffEntrySuggestedChange: file not found", **log_context, "gh.file_path": path, "gh.commit_oid": current_commit.oid)
      raise NotFoundError.new("File '#{path}' not found at commit #{current_commit.oid[0..7]}. This diff has recently been updated.")
    end

    @file_contents[path] = blob
  end

  def line_endings(blob)
    blob.has_windows_line_endings? ? "\r\n" : "\n"
  end

  def log_context
    ctx = {
      "code.namespace": self.class.name,
      "gh.repository.id": repository.id,
      "gh.tree_name": tree_name
    }
    ctx["gh.pull_request.id"] = pull_request.id if pull_request
    ctx
  end
end
