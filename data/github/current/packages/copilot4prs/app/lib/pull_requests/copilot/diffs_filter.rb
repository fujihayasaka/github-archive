# typed: strict
# frozen_string_literal: true

# Public: Filters diff entries to exclude any files we don't want to summarize. See #each for
# types of files we want to exclude from summarization.
#
# Examples:
#
#   filter = PullRequests::Copilot::DiffsFilter.new(diffs: pr.historical_comparison.diffs)
#   filter.to_a
#   # => ["#<GitHub::Diff::Entry>", …] # all results will have passed the filter
#
module PullRequests
  module Copilot
    class DiffsFilter
      include GitHub::Memoizer
      include Enumerable
      extend T::Generic

      Elem = type_member { { fixed: GitHub::Diff::Entry } }

      CONFIG_PATH = T.let(File.expand_path("./diffs_filter_config.yml", File.dirname(__FILE__)), String)
      CONFIG = T.let(YAML.safe_load_file(CONFIG_PATH), T::Hash[String, T.untyped]) # rubocop:disable Sorbet/ForbidTUntyped
      DEFAULT_EXCLUDES = T.let(CONFIG["globs"]["exclude"], T::Array[String])
      FNMATCH_FLAGS = T.let(File::FNM_PATHNAME | File::FNM_CASEFOLD | File::FNM_DOTMATCH, Integer)

      MAX_FILES = 20
      MAX_CHANGES = 400

      sig { returns(T.any(GitHub::Diff, T::Array[GitHub::Diff::Entry])) }
      attr_reader :diffs

      sig { returns(T::Set[String]) }
      attr_reader :include_globs

      sig { returns(T::Set[String]) }
      attr_reader :exclude_globs

      sig { returns(T::Set[String]) }
      attr_reader :copilot_content_exclusion

      # Public: Initializes a new DiffFilter object.
      #
      # diffs: An array of GitHub::Diff::Entry objects.
      sig { params(diffs: T.any(GitHub::Diff, T::Array[GitHub::Diff::Entry]), copilot_content_exclusion: T.nilable(T::Array[T.nilable(String)])).void }
      def initialize(diffs:, copilot_content_exclusion: nil)
        @diffs = diffs
        @copilot_content_exclusion = T.let(Set.new(copilot_content_exclusion), T::Set[String])
        @include_globs = T.let(Set.new, T::Set[String])
        @exclude_globs = T.let(Set.new(DEFAULT_EXCLUDES), T::Set[String])
      end

      # Public: Provides Enumerable behavior that excludes any
      # diff entries that match the following rules:
      #
      #   - no binary files
      #   - no entries with more additions/deletions than MAX_CHANGES
      #   - no entries that have been truncated or skipped when generating the diff
      #   - no entries that match our configured excluded glob patterns
      #   - if configured, only entries that match include glob patterns
      #   - does not iterate over MAX_FILES
      #
      # Returns nothing.
      sig { override.params(block: T.proc.params(arg0: Elem).returns(BasicObject)).void }
      def each(&block)
        start_time = Time.current
        excluded_paths = fnmatch(exclude_globs, paths)
        copilot_content_exclusion_paths = fnmatch(copilot_content_exclusion, paths)
        included_paths = fnmatch(include_globs, paths) if include_globs.any?
        files_count = 0

        entries = @diffs.each do |entry|
          break if files_count >= MAX_FILES

          next if entry.truncated? || entry.skipped?
          next if entry.changes > MAX_CHANGES
          next if entry.binary?
          next if excluded_paths.include?(entry.path)
          next if copilot_content_exclusion_paths.include?(entry.path)
          next if included_paths && !included_paths.include?(entry.path)

          files_count += 1
          yield entry
        end
        GitHub.dogstats.timing_since("copilot.prompt.filter_diffs", start_time, tags: ["size:#{@diffs.size}"])
        entries
      end

      private

      sig { returns(T::Array[String]) }
      memoize def paths
        @diffs.map(&:path)
      end

      # Private: Selects paths that match any of the given glob patterns.
      #
      # Returns an Array of String paths.
      sig { params(globs: T::Set[String], paths: T::Array[String]).returns(T::Array[String]) }
      def fnmatch(globs, paths)
        paths.select do |path|
          globs.any? { |glob| File.fnmatch?(glob, path, FNMATCH_FLAGS) }
        end
      end
    end
  end
end
