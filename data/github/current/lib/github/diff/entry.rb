# typed: true
# frozen_string_literal: true

require "set"

# An individual file's change information.
#
# Care must been taken to ensure this class is marshalable for cache,
# using only basic data types.
class GitHub::Diff::Entry
  include GitHub::Encoding
  include GitHub::UTF8

  DIRECTORY_MODE = "040000".freeze
  SYMLINK_MODE   = "120000".freeze
  SUBMODULE_MODE = "160000".freeze

  # Defines the encodings that don't get transcoded.  See #unicode_text.
  UNICODE_PASSTHROUGH = Set.new([:binary, UTF8])

  # The original SHA1s used to generate the diff. These will be the same for
  # all entries.
  attr_accessor :a_sha, :b_sha

  # Whether the diff ignores changes in whitespace.
  attr_accessor :whitespace_ignored
  alias whitespace_ignored? whitespace_ignored

  attr_accessor :context_lines

  # Path, mode, and blob sha1 for both sides of the change.
  attr_reader   :a_path, :b_path
  attr_reader   :a_path_raw, :b_path_raw
  attr_accessor :a_blob, :b_blob
  attr_accessor :a_mode, :b_mode

  def a_path=(path)
    if path
      @a_path_raw = path.dup
      @a_path = utf8(path.dup)
    else
      @a_path_raw = nil
      @a_path = nil
    end
  end

  def b_path=(path)
    if path
      @b_path_raw = path.dup
      @b_path = utf8(path.dup)
    else
      @b_path_raw = nil
      @b_path = nil
    end
  end

  # Number of added and deleted lines in the diff.
  attr_accessor :additions, :deletions

  # The similarity and dissimilarity index scores as an integer between 0 and
  # 100. Only provided on renames and copies.
  attr_accessor :similarity, :dissimilarity

  # The extended headers for the entry in a single string.
  attr_accessor :extended_header_text

  # The unified diff text for the change in a single string.
  attr_accessor :text

  # rename or copy
  attr_accessor :rename_type

  # If the diff was truncated due to size, this will be set to a string
  # saying why.  e.g., "maximum diff size exceeded."
  attr_accessor :truncated_reason

  # If this individual file exceeded one of the per-file limits, this will be
  # set to a string representing the limit that was violated. "size" or "line"
  attr_accessor :skipped_reason

  # Create a new diff entry.
  def initialize(old_path, new_path)
    self.a_path, self.b_path = old_path, new_path
    @a_blob = @b_blob = nil
    @a_mode = @b_mode = nil
    @whitespace_ignored = false
    @binary = false
    @rename_type = nil
    @extended_header_text = nil
    @text = nil

    @additions = @deletions = 0
    @lines = nil
  end

  # Create diff entry from a GitHub::Diff::Delta or GitRPC::Diff::Summary::Delta (which is a subclass
  #    of GitHub::Diff::Delta)
  def self.from(diff:, delta:)
    new(delta.old_file.path, delta.new_file.path).tap do |entry|
      entry.a_sha = diff.parsed_sha1
      entry.b_sha = diff.parsed_sha2
      entry.whitespace_ignored = diff.ignore_whitespace
      entry.context_lines = diff.context_lines[entry.path] if diff.context_lines

      entry.a_mode = delta.old_file.mode
      entry.b_mode = delta.new_file.mode

      entry.a_blob = delta.old_file.oid
      entry.b_blob = delta.new_file.oid

      entry.similarity = delta.similarity

      if delta.is_a? GitRPC::Diff::Summary::Delta
        entry.additions = delta.additions || 0
        entry.deletions = delta.deletions || 0
        entry.binary = delta.binary?
      end

      if delta.removed?
        entry.b_mode = nil
        entry.b_path = nil
        entry.b_blob = nil
      elsif delta.added?
        entry.a_mode = nil
        entry.a_path = nil
        entry.a_blob = nil
      end

      if delta.renamed?
        entry.rename_type = "rename"
      elsif delta.copied?
        entry.rename_type = "copy"
      end
    end
  end

  # The logical path name for this entry.
  def path
    b_path || a_path
  end

  def path_raw
    b_path_raw || a_path_raw
  end

  def path_digest
    Digest::SHA256.hexdigest(path)
  end

  # Is this a binary file?
  attr_accessor :binary
  alias binary? binary

  # Total number of lines changed in either additions or deletions.
  def changes
    additions + deletions
  end

  # Generate a diffstat line that fits within the specified
  # number of columns and using the given symbols.
  def stats(columns = 80, addition_symbol = "+", deletion_symbol = "-")
    adjust = changes > columns ? columns / changes.to_f : 1.0
    (addition_symbol * (additions * adjust)) +
    (deletion_symbol * (deletions * adjust))
  end

  def line_count
    lines ? lines.size : 0
  end

  def byte_count
    text ? text.bytesize : 0
  end

  # The diff text in UTF-8 encoding
  #
  # Returns the diff text as a UTF-8 string.
  def unicode_text
    @unicode_text ||= transcode_text
  end

  # Private: Helper to transcode diff text into valid UTF-8
  #
  # Returns the diff text as a UTF-8 string
  def transcode_text
    return nil if @text.nil?

    case text_encoding
    when :binary
      # force a UTF-8 scrub
      encoding = UTF8
    when UTF8
      @text.force_encoding(UTF8)
      @text.scrub! unless @text.valid_encoding?
      return @text
    else
      encoding = UTF8
    end

    begin
      transcode @text, encoding, UTF8
    rescue ArgumentError
      @text
    end
  end

  # Try to guess the encoding
  #
  # content - a string
  #
  # Returns a Hash, with :encoding, :confidence, :type and optionally :language
  #         this will return nil if an error occurred during detection or
  #         no valid encoding could be found
  def text_encoding_guess
    return @text_encoding_guess if defined?(@text_encoding_guess)
    @text_encoding_guess = guess(@text) if @text
    @text_encoding_guess ||= {}
  end

  # Simple helper to get the guessed encoding for the diff.
  #
  # Returns a String encoding, or :binary for binary diffs.
  def text_encoding
    @text_encoding ||= binary_text? ? :binary : text_encoding_guess[:encoding]
  end

  # Gets whether Charlock Holmes thinks this diff is binary or unknown.
  #
  # Returns true or false.
  def binary_text?
    text_encoding_guess[:type] == :binary || text_encoding_guess.empty?
  end

  # The raw diff text lines. The first line will always be a diff hunk
  # marker, or nil when the diff did not modify any blob content.
  #
  # Returns an Array of strings NOT terminated by "\n" characters.
  def lines
    @lines ||= unicode_text ? unicode_text.split("\n") : []
  end

  # Yields a [type, text, position, left, right, current, related] tuple.
  #     type - Type of line. One of :hunk, :context, :injected_context,
  #            :addition, :deletion.
  #     text - Raw diff line text with prefix characters.
  # position - The zero-based line offset into the raw diff text for this
  #            set of changes.
  #     left - Integer line offset into the file on the left side of the diff
  #    right - Integer line offset into the file on the right side of the diff
  #  current - Either left or right, depending on the type of line.
  #  related - If this diff line is related to another, this is the String text
  #            of the related line.
  #
  # Returns nothing.
  def each_line(&block)
    enumerator.each(&block)
  end

  def enumerator
    @enumerator ||= GitHub::Diff::RelatedLinesEnumerator.new(lines).each
  end

  def basic_enumerator
    @basic_enumerator ||= GitHub::Diff::Enumerator.new(lines).each
  end

  def split_lines
    @split_lines ||= GitHub::Diff::SplitLinesEnumerator.new(lines).each
  end

  def lfs_pointers
    @lfs_pointers ||= Media::Pointer.parse_diff(text)
  end

  def lfs_pointer?
    lfs_pointers.any?
  end

  # Public: Iterates through the diff entry until it finds the matching line.
  #
  # blob_position - the 0 indexed blob line for the comment
  # left_side     - a Boolean when true, `blob_position` refers to the left hand side blob.
  #                 Right side otherwise
  #
  # Returns the Integer position (offset) in the diff text itself for the matching line,
  # or `nil` if it is not present.
  def position_for(blob_position, left_side)
    return nil if blob_position.nil?
    enumerator.each do |current_line|
      if left_side
        return current_line.position if (current_line.deletion? || current_line.context?) && current_line.blob_left == blob_position
        break nil if current_line.blob_left > blob_position
      else
        return current_line.position if (current_line.addition? || current_line.context?) && current_line.blob_right == blob_position
        break nil if current_line.blob_right > blob_position
      end
    end
  end

  # Public: This calculates width of the line number column. The line number
  # column has 10px padding on each side (see .diff-num), hence the 20. Then
  # we add 8px per digit to it. When the result is less than 40px, we use
  # 40px instead to accomodate blob expander and ellipsis.
  #
  # Returns the width in pixel.
  def col_width
    lines = each_line.to_a
    line_number = [lines.last.left, lines.last.right].max
    [20 + (line_number.to_s.size * 8), 40].max
  end

  # The entry's modification status. This is a single character string
  # describing how the entry was changed.
  def status
    case
    when added?;        "A"
    when deleted?;      "D"
    when renamed?;      "R"
    when copied?;       "C"
    when modified?;     "M"
    when mode_changed?; "T"
    when unchanged?;    "U"
    when !valid?;       "I"
    else
      fail "can't establish entry status"
    end
  end

  LABELS = {
    "A" => "added",
    "D" => "removed",
    "R" => "renamed",
    "C" => "copied",
    "M" => "modified",
    "T" => "changed",
    "U" => "unchanged",
    "I" => "changed",   # unknown changes due to truncated diff
  }

  # The longer version of status.
  def status_label
    LABELS[status]
  end

  # This entry is invalid if both a_blob and b_blob are nil.
  # That can happen if it is from a large diff that was truncated.
  def valid?
    !(b_blob.nil? && a_blob.nil?)
  end

  # If a diff entry is skipped or truncated, a reason will be
  # set, but the diff will actually contain no data, even if it would
  # were the limits not present.
  def loaded?
    !truncated? && !skipped?
  end

  # Skipped because of line or size limits
  def too_big?
    skipped_reason == "size" || skipped_reason == "line"
  end

  alias present? loaded?

  ##
  # Status predicates

  def added?
    rename_type.nil? && a_path.nil?
  end

  def deleted?
    rename_type.nil? && b_path.nil?
  end

  def renamed?
    rename_type == "rename"
  end

  def copied?
    rename_type == "copy"
  end

  def modified?
    rename_type.nil? &&
      blob_modified?
  end

  def blob_modified?
    (a_blob && b_blob && a_blob != b_blob) ||
      (
        a_mode != b_mode &&
        !NON_FILE_MODES.include?(a_mode) &&
        !NON_FILE_MODES.include?(b_mode)
      ) ||
      (
        a_path && b_path && a_blob != b_blob &&
        SUBMODULE_MODE == a_mode &&
        SUBMODULE_MODE == b_mode
      )
  end

  def renamed_and_modified?
    renamed? && blob_modified?
  end

  NON_FILE_MODES = [
    DIRECTORY_MODE, # directory
    SYMLINK_MODE,   # symlink
    SUBMODULE_MODE,  # submodule
  ]

  def mode_changed?
    return false if a_mode == b_mode

    NON_FILE_MODES.include?(a_mode)
  end

  def unchanged?
    a_blob && a_blob == b_blob &&
    a_mode && a_mode == b_mode &&
    rename_type.nil?
  end

  def symlink?
    a_mode == SYMLINK_MODE || b_mode == SYMLINK_MODE
  end

  def submodule?
    a_mode == SUBMODULE_MODE || b_mode == SUBMODULE_MODE
  end

  # Returns true if this file's diff had too many lines
  def skipped_for_max_lines?
    skipped_reason == "line"
  end

  # Returns true if this file's diff had too many bytes
  def skipped_for_max_size?
    skipped_reason == "size"
  end

  def truncated?
    !truncated_reason.nil?
  end

  def skipped?
    !skipped_reason.nil?
  end

  # There are many entry types where it's not possible to inject context lines.
  # For example if all lines in an entry were added, they are all already expanded
  # and no further context lines can be injected.
  # In the case of a submodule or a binary entry, there is no text to display,
  # so there aren't any further context lines we can inject.
  def can_inject_context?
    if added? || deleted? || truncated? || submodule? || text.blank? || skipped?
      false
    else
      true
    end
  end

  def header_text
    "diff --git a/#{a_path || b_path} b/#{b_path || a_path}\n"
  end

  def to_diff_text
    header = header_text + extended_header_text

    if truncated?
      header + "Truncating diff: #{truncated_reason}\n"
    elsif skipped?
      header + "Omitting #{additions} additions, #{deletions} deletions due to #{skipped_reason} limit.\n"
    elsif text.blank?
      header
    else
      header + "#{text}\n"
    end
  end

  PACKER = lambda do |obj|
    GitHub::Cache::Codec.factory.pack({
      a_path_raw: obj.a_path_raw&.b,
      b_path_raw: obj.b_path_raw&.b,
      a_sha: obj.a_sha,
      b_sha: obj.b_sha,
      whitespace_ignored: obj.whitespace_ignored,
      a_blob: obj.a_blob,
      b_blob: obj.b_blob,
      a_mode: obj.a_mode,
      b_mode: obj.b_mode,
      additions: obj.additions,
      deletions: obj.deletions,
      similarity: obj.similarity,
      dissimilarity: obj.dissimilarity,
      extended_header_text: obj.extended_header_text,
      text: obj.text,
      rename_type: obj.rename_type,
      truncated_reason: obj.truncated_reason,
      skipped_reason: obj.skipped_reason,
      binary: obj.binary,
      context_lines: obj.context_lines&.map { |range| [range.begin, range.end, range.exclude_end?] },
    })
  end

  UNPACKER = lambda do |data|
    hash = GitHub::Cache::Codec.factory.unpack(data)
    entry = GitHub::Diff::Entry.new(hash[:a_path_raw], hash[:b_path_raw])
    entry.a_sha = hash[:a_sha]
    entry.b_sha = hash[:b_sha]
    entry.whitespace_ignored = hash[:whitespace_ignored]
    entry.a_blob = hash[:a_blob]
    entry.b_blob = hash[:b_blob]
    entry.a_mode = hash[:a_mode]
    entry.b_mode = hash[:b_mode]
    entry.additions = hash[:additions]
    entry.deletions = hash[:deletions]
    entry.similarity = hash[:similarity]
    entry.dissimilarity = hash[:dissimilarity]
    entry.extended_header_text = hash[:extended_header_text]
    entry.text = hash[:text]
    entry.rename_type = hash[:rename_type]
    entry.truncated_reason = hash[:truncated_reason]
    entry.skipped_reason = hash[:skipped_reason]
    entry.binary = hash[:binary] || false
    entry.context_lines = hash[:context_lines]&.map { |args| Range.new(*args) }
    entry
  end
end
