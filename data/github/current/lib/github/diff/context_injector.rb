# typed: false
# frozen_string_literal: true

require "github/diff/parser"

FILE_MODE = "100644"

# Used by GitHub::Diff to support the :context_lines option.
class GitHub::Diff::ContextInjector
  # Public: Create a new ContextInjector to transform the text of a diff to
  # include additional context lines.
  #
  # diff_text     - A String containing a unified diff as formatted by Git
  # context_lines - A Hash of with path Strings as keys and Arrays of line
  #                 number Integer Ranges as values. The ranges can overlap
  #                 and are not required to be sorted.
  # sha2          - A String containing the commit oid of the right side of
  #                 the diff. This is used to fetch blobs that provide the
  #                 additional context lines.
  # rpc           - A GitRPC::Client instance pointing to the repository that
  #                 was the source of the `diff_text`. This is used to fetch
  #                 blobs that provide the additional context lines.
  # repo          - A Repository instance or other instance supporting
  #                 SpokesAdapter pointing to the repository that
  #                 was the source of the `diff_text`. This is used to fetch
  #                 blobs that provide the additional context lines.
  def initialize(diff_text:, context_lines:, sha2:, rpc:, repo:)
    @diff_text = GitHub::Encoding.try_guess_and_transcode(diff_text)
    @context_lines = context_lines
    @sha2 = sha2
    @rpc = rpc
    @expanded_diff = nil
    @repo = repo
  end

  # Public: Expand the original diff text to include the requested lines of
  # context.
  #
  # Returns a String
  def expanded_diff
    return @expanded_diff if @expanded_diff

    entries = []
    parser = GitHub::Diff::Parser.new(@diff_text)
    parser.each { |e| entries.push(e) }

    @blobs_by_path = fetch_context_blobs(entries)

    # If all injected context lines are for paths
    # that don't actually exist at the sha (or in the repo)
    # then we can abort early.
    return @expanded_diff = @diff_text if @blobs_by_path.empty?
    @expanded_diff = ""
    entries.each do |entry|
      if entry.can_inject_context?
        emit_expanded_entry(entry)
      else
        @expanded_diff += entry.to_diff_text
      end
    end

    @expanded_diff
  end

  private

  def emit_expanded_entry(entry)
    unless @blobs_by_path[entry.b_path].present?
      return @expanded_diff += entry.to_diff_text
    end

    line_count_delta = 0
    if ranges = @context_lines[entry.b_path]
      text = @blobs_by_path[entry.b_path]
      line_count = text.count("\n")
      sanitized_ranges = sanitize_ranges(ranges, line_count)
      ranges = combine_ranges(sanitized_ranges)
      extracted_lines = extract_lines(text, ranges)
    else
      ranges = []
    end

    diff_lines = entry.each_line
    hunks = []

    # Build up the hunks array by iterating through every desired context
    # line number.
    Enumerator::Chain.new(*ranges).each do |context_row|
      # Append lines from the original diff that are <= the context line
      begin
        appended_first_hunk = false
        loop do
          if diff_lines.peek.type == :hunk
            diff_lines.next
          end
          if diff_lines.peek.right <= context_row
            line = diff_lines.next
            if !appended_first_hunk
              if line.type == :deletion
                append_to_hunks(hunks, line.left, line.type, line.text + "\n")
              else
                append_to_hunks(hunks, line.right, line.type, line.text + "\n")
              end
            else
              append_to_hunks(hunks, line.right, line.type, line.text + "\n")
            end
            appended_first_hunk = true
          else
            break
          end
        end
      rescue StopIteration
      end

      # Append the context line itself. If a line is already present at the
      # specified right line number, this will be a no-op.
      append_to_hunks(hunks, context_row, :context, "~" + extracted_lines[context_row])
    end

    # Append any lines from the original diff that remain following the
    # injected context lines.
    begin
      loop do
        line = diff_lines.next
        if line.type != :hunk
          append_to_hunks(hunks, line.right, line.type, line.text + "\n")
        end
      end
    rescue StopIteration
    end

    @expanded_diff += entry.header_text
    if entry.extended_header_text
      @expanded_diff += entry.extended_header_text
    end
    hunks.each do |hunk|
      @expanded_diff += hunk.header
      @expanded_diff += hunk.lines.join
    end
  end

  # Private: Appends the given diff line to the previous hunk if one exists
  # and there is no gap between the end of the previous hunk and the
  # right_offset of the appended line. If no hunk exists or there is a gap, a
  # new hunk is created first.
  def append_to_hunks(hunks, right_offset, type, text)
    if hunks.empty?
      hunks.push(Hunk.new(right_offset, right_offset, 0, 0))
    end

    if right_offset > hunks.last.right_offset + hunks.last.right_count
      lines_delta = hunks.last.right_offset + hunks.last.right_count - hunks.last.left_offset - hunks.last.left_count
      left_offset = right_offset - lines_delta
      hunks.push(Hunk.new(left_offset, right_offset, 0, 0))
    end

    if type != :context || right_offset == hunks.last.right_offset + hunks.last.right_count
      hunks.last.add_line(type, text)
    end
  end

  # Private: Helper that sorts, merges, and constrains an array of ranges of
  # line numbers that we want to make visible in the diff.
  #
  # ranges     - an Array of Integer line number Ranges
  # line_count - an Integer representing the number of lines in the file
  #
  # The given ranges are expanded by 3 lines in either direction, if
  # possible. If doing this causes the ranges to overlap, they are merged.
  #
  # Returns an Array of Integer line number Ranges.
  def sanitize_ranges(ranges, line_count)
    ranges = ranges.map do |r|
      first = [1, r.first].max
      if first <= line_count
        last = [line_count, r.last].min
        first..last
      else
        nil
      end
    end
    ranges.compact!
    ranges.sort_by! { |r| r.first }
  end

  def combine_ranges(ranges)
    expanded_ranges = []
    i = 0
    while i < ranges.length
      first = ranges[i].first
      while i < ranges.length - 1 && ranges[i].last + 1 >= ranges[i + 1].first
        i += 1
      end
      last = ranges[i].last
      expanded_ranges.push(first..last)
      i += 1
    end

    expanded_ranges
  end

  # TODO: If text is large, calling :lines and allocating a giant array of
  # strings may end up being pretty costly. We may want to optimize this by
  # scanning the text for newlines to minimize intermediate data. That's why
  # I have structured this as a separate method.
  def extract_lines(text, ranges)
    extracted_lines = {}
    all_lines = text.lines
    ranges.each do |range|
      range.each do |i|
        extracted_lines[i] = all_lines[i - 1]
      end
    end
    extracted_lines
  end

  # Private: Called when ContextInjector is initialized to fetch
  # all the data we need from GitRPC
  # Groups blobs by path for easier lookup
  #
  # Returns a Hash of blob text by blob paths
  def fetch_context_blobs(entries)
    # Only fetch blobs for paths corresponding to valid entries. If an entry
    # is truncated or binary, we won't inject context lines for it. If an entry is an
    # addition or removal, it also doesn't make sense to inject context
    # lines.

    paths = entries.select { |entry| (entry.modified? || entry.renamed_and_modified?) && !entry.truncated? && !entry.binary && @context_lines.key?(entry.b_path) }.map(&:b_path)
    blob_oids = @repo.read_blob_oids(
      paths.map { |path| [@sha2, path] },
      skip_bad: true,
    )

    # Preserve only paths that corresponded to a valid blob oid. Maintain a
    # 1:1 correspondence between the valid_paths and the compacted blob_oids
    # array.
    valid_paths = []
    paths.each_with_index do |path, i|
      valid_paths.push(path) if blob_oids[i].present?
    end
    blob_oids.compact!

    blobs_by_path = Hash.new
    @rpc.read_blobs(blob_oids).each_with_index do |blob, i|
      blob_data, binary = blob.values_at("data", "binary")
      next if binary
      blobs_by_path[valid_paths[i]] = GitHub::Encoding.transcode(blob_data, blob_data.encoding.to_s, Encoding::UTF_8.to_s)
    end
    blobs_by_path
  end

  class Hunk
    attr_reader :left_offset
    attr_reader :right_offset
    attr_reader :left_count
    attr_reader :right_count
    attr_reader :lines

    def initialize(left_offset, right_offset, left_count, right_count)
      @left_offset = left_offset
      @right_offset = right_offset
      @left_count = left_count
      @right_count = right_count
      @lines = []
    end

    def header
      left = left_count == 1 ? "-#{left_offset}" : "-#{left_offset},#{left_count}"
      right = right_count == 1 ? "+#{right_offset}" : "+#{right_offset},#{right_count}"
      "@@ #{left} #{right} @@\n"
    end

    def add_line(type, text)
      case type
      when :deletion
        @left_count += 1
      when :addition
        @right_count += 1
      when :context
        @left_count += 1
        @right_count += 1
      end
      @lines.push(text)
    end
  end
end
