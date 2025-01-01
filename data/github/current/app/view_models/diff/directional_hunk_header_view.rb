# typed: true
# frozen_string_literal: true

module Diff
  # Controls the display of a diff hunk header
  class DirectionalHunkHeaderView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include DiffHelper
    include UrlHelper

    # The line numbers for the left and right sides of the diff.
    attr_reader :left, :right

    # Previous line numbers for left and right sides of the diff.
    attr_reader :last_left, :last_right

    # Used as an offset for the size of headers rendered in the blob excerpt
    attr_reader :left_hunk_size, :right_hunk_size

    # The hunk headers position in the original diff output.
    attr_reader :position

    # The CodeLinesPartialView or DirectionalBlobExcerpt to which this header belongs
    attr_reader :parent_view

    # When iterating through the original diff, the `GitHub::Diff::Line` instance for this header.
    # Set to :last when generating a trailing header to expand down the remainder of the blob.
    attr_reader :line

    # Attribute set from parent views that indicates whether or not this directional hunk header
    # is being viewed within the context of a pull request or not. Used to ultimately generate
    # expansion urls that allow for adding new commments on a pull request
    attr_reader :pull_request_context

    delegate :blob_line_count, :in_wiki_context, :blob_sha, :path, :mode, :current_repository, to: :parent_view

    def after_initialize
      if line
        if line == :last
          @left = parent_view.blob_line_count + 1
          @right = parent_view.blob_line_count + 1
        else
          initialize_from_line
        end
      else
        initialize_from_parent_view
      end

      @last_left ||= parent_view.last_left if parent_view.respond_to?(:last_left)
      @last_right ||= parent_view.last_right if parent_view.respond_to?(:last_right)
    end

    def header_text
      @header_text unless eof_expander?
    end

    def expandable?
      parent_view.expandable? && (expandable_up? || expandable_down?)
    end

    def eof_expander?
      right > blob_line_count
    end

    def first_expander?
      !last_right || last_right <= 0
    end

    def lines_elided
      right - 1 - (last_right || 0)
    end

    def lines_elided?
      lines_elided > 0
    end

    def expandable_up?
      lines_elided? && !eof_expander?
    end

    def expandable_down?
      lines_elided? && !first_expander?
    end

    def will_expand_all_lines?
      lines_elided <= Blob::BlobExcerpt::DEFAULT_OFFSET
    end

    def single_expander?
      (expandable_up? ^ expandable_down?) || condensed_expander?
    end

    def condensed_expander?
      expandable_down? && expandable_up? && will_expand_all_lines?
    end

    def up_left_range
      up_range(last_left, left)
    end

    def up_right_range
      up_range(last_right, right)
    end

    def down_left_range
      down_range(last_left, left)
    end

    def down_right_range
      down_range(last_right, right)
    end

    def expand_url(direction: :up, diff_type: :unified)
      params = {
        diff: diff_type,
        last_left: last_left,
        last_right: last_right,
        left_hunk_size: left_hunk_size,
        right_hunk_size: right_hunk_size,
        left: left,
        right: right,
        in_wiki_context: in_wiki_context,
        pull_request_context: pull_request_context,
      }
      params[:direction] = direction unless condensed_expander?

      diff_blob_excerpt_url(blob_sha, path, mode, params)
    end

    def anchor
      diff_path_anchor(path)
    end

    private

    def up_range(last, current)
      return unless expandable_up?

      if expandable_down?
        "#{midpoint(last, current)}-#{current - 1}"
      else
        "#{last.to_i + 1}-#{current - 1}"
      end
    end

    def down_range(last, current)
      return unless expandable_down?

      if expandable_up?
        "#{last.to_i + 1}-#{midpoint(last, current) - 1}"
      else
        "#{last.to_i + 1}-#{current - 1}"
      end
    end

    def midpoint(last, current)
      last + ((current - last) / 2)
    end

    # Internal: initialize the view using an instance of GitHub::Diff::Line.
    def initialize_from_line
      # the line number reported by GitHub::Diff:Line is the line the header itself would be on.
      # we aren't interested in that, we want the following line.
      @left = line.left + 1 unless left
      @right = line.right + 1 unless right
      @header_text = line.text
      @position = line.position

      if parsed_header_text = header_text&.match(/@@ -\d+,(\d+) \+\d+,(\d+) /)
        @left_hunk_size   = parsed_header_text[1].to_i
        @right_hunk_size  = parsed_header_text[2].to_i
      end
    end

    # Internal: initialize the view based on its parent view. The parent tested is Blob::DirectionalBlobExcerpt
    def initialize_from_parent_view
      @left = parent_view.left
      @right = parent_view.right
      @left_hunk_size = parent_view.left_hunk_size
      @right_hunk_size = parent_view.right_hunk_size
      @header_text = parent_view.hunk_header
    end
  end
end
