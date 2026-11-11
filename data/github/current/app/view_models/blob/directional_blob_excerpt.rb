# typed: true
# frozen_string_literal: true

class Blob::DirectionalBlobExcerpt < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  DEFAULT_OFFSET = 20

  attr_reader :blob
  delegate :path, :mode, to: :blob

  attr_reader :offset

  # The last_[left|right] and [left|right] describing the range of lines over which this
  # excerpt is expanding.
  attr_reader :original_last_left, :original_last_right
  attr_reader :original_left, :original_right

  # Left and right hunk sizes. Used to calculate the expanded hunk region when expanding up
  attr_reader :left_hunk_size, :right_hunk_size

  attr_reader :blob_line_count

  # is this excerpt a result of expanding up or down?
  attr_reader :direction

  attr_reader :in_wiki_context

  attr_reader :current_repository

  attr_reader :commentable

  # attributes used when generating the new adjusted hunk header for the excerpt. These are updated
  # to include the blob data as context lines and adjusting the starting line. Currently only applies
  # when expanding up as the size for the hunk header at the bottom of the excerpt is not altered by
  # the expansion.
  attr_reader :last_left, :last_right, :left, :right

  # Used to determine whether this blob excerpt context is being rendered
  # as a part of a pull request. This attribute will be shared with its child
  # partial views to engage in additional functionality relevant to pull
  # requests
  attr_reader :pull_request_context

  # ContextPartialView needs to know the lines to start iterating on. It uses these attributes to determine it.
  def right_hunk_start
    expanding_down? || expanding_full? ? original_last_right + 1 : right
  end

  def left_hunk_start
    expanding_down? || expanding_full? ? original_last_left + 1 : left
  end

  def after_initialize
    @blob_line_count = all_lines.count

    set_direction

    @original_left ||= blob_line_count + 1
    @original_right ||= blob_line_count + 1
    @original_last_left ||= 0
    @original_last_right ||= 0
    @left_hunk_size ||= 0
    @right_hunk_size ||= 0

    if @direction == :full
      @offset = nil
    else
      @offset ||= DEFAULT_OFFSET
    end

    size = lines.count

    if expanding_down?
      @last_left = original_last_left + size
      @last_right = original_last_right + size
      @left = original_left
      @right = original_right
    else
      @last_left = original_last_left
      @last_right = original_last_right
      @left = [original_left - size, 1].max
      @right = original_right - size
    end

    if expanding_up?
      # we need do the math here because it is possible to have hit the start of file earlier
      # on the left than the right when expanding up.
      @left_hunk_size  += original_left - left if left_hunk_size
      @right_hunk_size += size if right_hunk_size
    end
  end

  def hunk_header
    return nil if left_hunk_size.nil? || right_hunk_size.nil?
    "@@ -#{left},#{left_hunk_size} +#{right},#{right_hunk_size} @@"
  end

  # always display the header when at the top of the file.
  # never display the header if the right is one line or less after the last right
  def display_top_hunk_header?
    return false if expanding_down? || expanding_full?
    right == 1 || right - 1 > last_right
  end

  # display the bottom hunk when there are still lines left to show
  def display_bottom_hunk_header?
    return false if expanding_up?
    last_right + 1 < right
  end

  def empty?
    lines.empty?
  end

  def expanding_up?
    !expanding_down?
  end

  def expanding_down?
    direction == :down
  end

  def expanding_full?
    direction == :full
  end

  def blob_sha
    blob&.sha
  end

  def all_lines
    return @all_lines if defined?(@all_lines)

    @all_lines = blob.colorized_lines
    @all_lines
  end

  def lines
    return @lines if defined?(@lines)

    # subtract 1 because all_lines is 0 based
    @lines = all_lines.slice(hunk_start - 1, hunk_size) || []
  end

  # just to satisy the DirectionalHunkHeaderView. blob excerpts are always expandable.
  def expandable?
    true
  end

  def hunk_start
    return @hunk_start if defined?(@hunk_start)
    @hunk_start = compute_hunk_start
  end

  private

  def compute_hunk_start
    return original_last_right + 1 if expanding_down?
    return [original_last_right + 1, original_right].min if expanding_full?
    start = original_right - offset
    return original_last_right + 1 if start <= original_last_right

    start
  end

  def hunk_size
    return @hunk_size if defined?(@hunk_size)
    @hunk_size = compute_hunk_size(hunk_start)
  end

  def compute_hunk_size(start)
    stop = original_right
    stop = [start + offset, original_right].min if expanding_down?
    stop - start
  end

  def set_direction
    return @direction = @direction.to_sym if direction

    # legacy requests will not have values for these on end blob headers. We know the direction
    # maps to down in this case. This can be removed when all requests are submitting the
    # direction param.
    if @original_left == 0 && @original_right == 0
      @direction = :down
      @original_left = blob_line_count + 1
      @original_right = blob_line_count + 1
    else
      @direction = :up
    end
  end
end
