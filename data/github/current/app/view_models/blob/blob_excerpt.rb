# typed: true
# frozen_string_literal: true

class Blob::BlobExcerpt < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  DEFAULT_OFFSET = 20

  attr_reader :blob, :path, :sha, :mode

  attr_reader :offset

  attr_reader :prev_line_left_start, :prev_line_right_start
  attr_reader :next_line_left_start, :next_line_right_start

  # Left and right starting line numbers for hunk header
  attr_reader :left_hunk_start, :right_hunk_start

  # Left and right hunk sizes
  attr_reader :left_hunk_size, :right_hunk_size

  attr_reader :hunk_header

  attr_reader :lines

  attr_reader :blob_line_count

  attr_reader :in_wiki_context
  def after_initialize
    @offset ||= DEFAULT_OFFSET

    all_lines = blob.colorized_lines

    @blob_line_count = all_lines.count

    @right_hunk_start = compute_hunk_start(@prev_line_right_start, @next_line_right_start, @offset)
    @left_hunk_start  = compute_hunk_start(@prev_line_left_start, @next_line_left_start, @offset)

    size = compute_hunk_size(@right_hunk_start, @next_line_right_start, @offset, all_lines.count)
    @left_hunk_size  += size if @left_hunk_size
    @right_hunk_size += size if @right_hunk_size

    @lines = all_lines.slice(@right_hunk_start - 1, size) || []

    # no hunk header for an empty excerpt or if we've joined the previous hunk
    # (unless it's at the top of the file)
    if @lines.any? && (@right_hunk_start == 1 || @right_hunk_start - 1 != @prev_line_right_start) && @left_hunk_size && @right_hunk_size
      @hunk_header = "@@ -#{@left_hunk_start},#{@left_hunk_size} +#{@right_hunk_start},#{@right_hunk_size} @@"
    end
  end

  def empty?
    self.lines.empty?
  end

  private

  def compute_hunk_start(prev_start, next_start, offset)
    # Calculate the start of the window
    start = next_start ? next_start - offset : prev_start + 1
    # Ensure we don't go beyond the line number above us
    [1, start, (prev_start ? prev_start + 1 : 1)].max
  end

  def compute_hunk_size(start, next_start, offset, max)
    # Calculate the end of the window
    stop = next_start ? next_start - 1 : start - 1 + offset
    stop = [stop, max].min
    stop - start + 1
  end
end
