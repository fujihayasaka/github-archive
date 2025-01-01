# typed: true
# frozen_string_literal: true

class PullRequestReviewComment

  # Public: A Plain Old Ruby Object (PORO) used for validating and rendering the
  # suggested change selection.
  class SuggestedChangeSelection

    def self.from_persisted_comment(comment)
      if comment.nil? || comment.outdated?
        new(outdated: true)
      else
        new(
          pull: comment.pull_request,
          original_selection: comment.original_selection,
        )
      end
    end

    def initialize(inputs)
      @pull = inputs[:pull]
      @start_commit_oid = inputs[:start_commit_oid]
      @end_commit_oid = inputs[:end_commit_oid]
      @base_commit_oid = inputs[:base_commit_oid]
      @path = inputs[:path]
      @start_line = inputs[:start_line]
      @start_side = inputs[:start_side]
      @line = inputs[:line]
      @side = inputs[:side]
      @outdated = inputs[:outdated]
      @original_selection = inputs[:original_selection]
    end

    def lines
      return @original_selection if @original_selection

      return [] if outdated?
      return [] unless valid_commits?
      return [] unless diff_entry

      end_position = diff_entry.position_for(@line - 1, @side.to_s.downcase == "left")

      return [] unless end_position

      start_position = if @start_line
        diff_entry.position_for(@start_line - 1, @start_side.to_s.downcase == "left")
      else
        end_position
      end

      diff_entry.lines[start_position..end_position]
    end

    def contains_deletions?
      lines.any? { |line| line.start_with?("-") }
    end

    def outdated?
      @outdated
    end

    def disabled?
      contains_deletions? ||
        outdated? ||
        !valid_commits? ||
        lines.empty?
    end

    def valid_commits?
      return true if @original_selection

      commits = [@start_commit_oid, @end_commit_oid, @base_commit_oid]
      return true if commits.all? { |commit| GitRPC::Util.valid_full_oid?(commit) }

      @end_commit_oid.present? &&
        GitRPC::Util.valid_full_oid?(@end_commit_oid) &&
        @pull.head_repository.commits.exist?(@end_commit_oid)
    end

    # Gets the diff entry at the given commit_id.
    #
    # Returns a GitHub::Diff::Entry or nil if the entry cannot be found.
    def diff_entry
      return @diff_entry if defined?(@diff_entry)
      @start_commit_oid ||= @pull.merge_base
      @base_commit_oid ||= @pull.merge_base

      context_lines = if FeatureFlag.vexi.enabled?(:comment_outside_the_diff, @pull.repository, default: false)
        context_range_starting_line = (@start_line || @line)
        context_range_ending_line   = @line
        { @path => [Range.new(context_range_starting_line, context_range_ending_line)] }
      else
        {}
      end
      @diff_entry = @pull.async_diff(
        start_commit_oid: @start_commit_oid,
        end_commit_oid: @end_commit_oid,
        base_commit_oid: @base_commit_oid,
        context_lines: context_lines
      ).then do |diff|
        diff.add_paths([@path])
        diff.maximize_single_entry_limits!
        diff
      end.sync.with_path(@path)
    end
  end
end
