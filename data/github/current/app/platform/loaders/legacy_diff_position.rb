# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    # This loader takes a selection of diff text (with the `+`, `-`, and ` ` line type
    # indicators included) along with a diff and path and returns the line in the underlying
    # blob corresponding to the last line in the selection. Matches are automatically batched
    # so that each diff only includes the minimal number of paths to satisy the requested
    # lines and also the minimal number of total diffs are calculated.
    #
    # This loader is typically used when `AdjustedBlobPosition` loader fails due to a missing
    # git object as generally that loader will be far more accurate.
    class LegacyDiffPosition < Platform::Loader
      def self.load(diff, path, match_text)
        self.for(diff.repo, diff.sha1, diff.sha2).load([path, match_text])
      end

      def initialize(repo, oid1, oid2)
        @repo = repo
        @oid1 = oid1
        @oid2 = oid2
      end

      attr_reader :repo, :oid1, :oid2

      def fetch(path_and_text_pairs)
        paths = path_and_text_pairs.map(&:first)
        diff = GitHub::Diff.new(repo, oid1, oid2, ignore_whitespace: false)
        diff.add_paths(paths)
        diff.maximize_single_entry_limits!

        positions = path_and_text_pairs.map do |path, match_text|
          next unless entry = diff[path]

          diff_position = diff_position_from_match(match_text, entry)
          next if diff_position.nil?

          convert_to_blob_position(diff_position, entry)
        end

        Hash[path_and_text_pairs.zip(positions)]
      end

      # Internal: Returns the diff line offset of the last line of the match text or nil
      #   if the match text could not be found in the given entry.
      def diff_position_from_match(match_text, entry)
        diff_text = entry.text.to_s.b + "\n"
        match_text = match_text.b
        if offset = diff_text.index(match_text)
          lines = diff_text[0, offset + match_text.size].split("\n")
          lines.size - 1
        else
          nil
        end
      end

      # Internal: Returns the appropriate blob position for the given diff position
      #
      # diff_position - the Integer line offset into the diff entry
      # diff_entry    - the GitHub::Diff::Entry in question
      #
      # Returns nil if the line can't be found or the diff entry is nil. Otherwise it returns
      # the blob position of the left blob if the line is a deletion, the right for an addition
      def convert_to_blob_position(diff_position, diff_entry)
        return nil if diff_entry.nil?

        line = diff_entry.basic_enumerator.to_a[diff_position]
        return nil if line.nil?
        line.deletion? ? line.blob_left : line.blob_right
      end
    end
  end
end
