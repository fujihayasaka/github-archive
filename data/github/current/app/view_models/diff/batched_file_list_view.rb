# typed: true
# frozen_string_literal: true

module Diff
  class BatchedFileListView
    DEFAULT_MAX_ENTRIES_BATCH_SIZE = GitHub::Diff::DEFAULT_MAX_FILES

    # File list view containing diff and repository
    attr_reader :file_list_view

    # Index of last entry of diff shown in a previous request/render
    attr_reader :start_entry_index

    # Bytes already rendered in previous requests
    attr_reader :already_shown_bytes

    # Lines already rendered in previous requests
    attr_reader :already_shown_lines

    # Maximum batch size for entries (full or empty)
    attr_reader :max_entries_batch_size

    def initialize(file_list_view, start_entry_index: 0,
                   already_shown_bytes: 0, already_shown_lines: 0,
                   max_entries_batch_size: DEFAULT_MAX_ENTRIES_BATCH_SIZE)
      @file_list_view          = file_list_view
      @start_entry_index       = start_entry_index.to_i
      @already_shown_bytes     = already_shown_bytes.to_i
      @already_shown_lines     = already_shown_lines.to_i
      @max_entries_batch_size  = max_entries_batch_size
    end

    # Public: Load toc and entries and diff necessary for rendering
    #
    # Returns nothing
    def prepare
      set_diff_deltas

      return if auto_load_limits_reached?

      diff.apply_auto_load_single_entry_limits!
      diff.load_diff
    end

    # Public: Returns the next entry after this batch
    #
    # Returns an Integer
    def next_start_entry_index
      start_entry_index + shown_entries_count
    end

    # Public: Are we at the end of the diff or hitting the max files limit of the diff summary?
    #
    # TODO Mid-term solution will be to merge BatchedFileListView and FileListView to
    # deduplicate this load more code
    #
    # Returns a Boolean
    def load_more?
      remaining_entries_after_batch > 0
    end

    # Public: Generate the list of file views we want to render for this batch
    #
    # Returns an Array of Diff::FileViews
    def file_views
      return @file_views if defined?(@file_views)

      @file_views = begin
        if auto_load_limits_reached?
          build_file_views_for_selected_deltas
        else
          file_list_view.each_diff.to_a
        end
      end

      @file_views.freeze
    end

    # Public: Diff instance at hand
    #
    # Returns a GitHub::Diff
    def diff
      file_list_view.diffs
    end

    private

    # Internal: Sets the deltas we want to load with this batch
    #
    # Returns nothing
    def set_diff_deltas
      diff.add_delta_indexes(entries_range.to_a)
    end

    # Internal: List summary deltas
    #
    # Returns an Array of GitRPC::Diff::Summary::Deltas
    def deltas
      diff.summary.deltas
    end

    # Internal: List of summary deltas selected for this batch
    #
    # Returns an Array of GitRPC::Diff::Summary::Deltas
    def selected_deltas
      indexed_selected_deltas.values
    end

    # Internal: Hash of summary deltas selected for this batch indexed by their index
    # within the total list of entries of the diff.
    #
    # Returns a Hash with GitRPC::Diff::Summary::Deltas as values and Integers as keys
    def indexed_selected_deltas
      return @indexed_selected_deltas if defined?(@indexed_selected_deltas)

      @indexed_selected_deltas = entries_range.each_with_object({}) do |index, hash|
        hash[index] = deltas[index]
      end
    end

    # Internal: Count of total maximal diff entries we render (over all batches)
    #
    # Returns an Integer
    def max_entries
      deltas.size
    end

    # Internal: Count of diff entries already rendered in previous batches
    #
    # Returns an Integer
    def already_shown_entries_count
      start_entry_index
    end

    # Internal: Count of diff entries (with or without text) rendered in this batch
    #
    # Returns an Integer
    def shown_entries_count
      file_views.size
    end

    # Internal: Count of remaining entries before this batch
    #
    # Returns an Integer
    def remaining_entries_before_batch
      max_entries - already_shown_entries_count
    end

    # Internal: Count of remaining entries after this batch
    #
    # Returns an Integer
    def remaining_entries_after_batch
      remaining_entries_before_batch - shown_entries_count
    end

    # Internal: Did we reach the auto limits with the previous batch?
    #
    # Returns a Boolean
    def auto_load_limits_reached?
      already_shown_bytes > max_auto_load_bytes ||
        already_shown_lines > max_auto_load_lines
    end

    # Internal: Maximum number of bytes we want to auto-load
    #
    # Returns an Integer
    def max_auto_load_bytes
      GitHub::Diff::AUTO_LOAD_MAX_TOTAL_BYTES
    end

    # Internal: Maximum number of lines we want to auto-load
    #
    # Returns an Integer
    def max_auto_load_lines
      GitHub::Diff::AUTO_LOAD_MAX_TOTAL_LINES
    end

    # Internal: Range of entries to load and render for this branch
    #
    # Returns a Range
    def entries_range
      return @entries_range if defined?(@entries_range)

      start_index = start_entry_index
      end_index = start_index + entries_batch_size

      @entries_range = (start_index...end_index)
    end

    # Internal: Number of entries to load and render for this branch. We might end
    # up with less when we don't manage to load diff texts for the whole range.
    #
    # Returns an Integer
    def entries_batch_size
      [remaining_entries_before_batch, max_entries_batch_size].min
    end

    # Internal: Build a list of file views for all selected deltas
    #
    # Returns an Array of Diff::FileViews
    def build_file_views_for_selected_deltas
      indexed_selected_deltas.map do |index, delta|
        diff_entry = GitHub::Diff::Entry.from(diff: diff, delta: delta)

        Diff::FileView.new(diff: diff_entry, diff_number: index,
                           repository: file_list_view.repository,
                           current_user: file_list_view.current_user)
      end
    end
  end
end
