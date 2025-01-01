# typed: true
# frozen_string_literal: true

module Diff
  # Controls the display of extra diff context lines
  class ContextPartialView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    # A Blob::BlobExcerpt.
    attr_reader :blob_excerpt

    # Blob and excerpt properties.
    attr_reader :blob, :blob_sha, :path, :mode, :lines

    # Total lines in the blob
    attr_reader :blob_line_count

    # Will disable expansion from the new hunk header if false.
    attr_reader :expandable

    # Was it expanded as the whole file, or just an individual hunk
    attr_reader :expanded_full

    # The anchor for the file or diff discussion.
    attr_reader :anchor

    # The first line number for the left and ride sides of this
    # context excerpt.
    attr_reader :right_start, :left_start

    # The next line number from the right side of the diff
    # immediately following the lines in this context.
    # -1 if there are no following lines.
    attr_reader :next_right

    # Used to determine whether this additional context is being rendered
    # as a part of a pull request, and if so, allow commenting on it
    attr_reader :pull_request_context

    # When rendered inside of a pull request page, used to determine
    # whether to allow the viewer to comment on lines
    attr_reader :commentable

    def after_initialize
      @expandable ||= false

      if !self.blob_excerpt.nil?
        @lines ||= self.blob_excerpt.lines
        @blob_line_count ||= self.blob_excerpt.blob_line_count
        @right_start ||= self.blob_excerpt.right_hunk_start
        @left_start ||= self.blob_excerpt.left_hunk_start
      end

      if !self.blob.nil?
        @blob_line_count ||= self.blob.lines.count
        @blob_sha ||= self.blob.oid
      end
    end

    def expandable?
      self.expandable
    end
  end
end
