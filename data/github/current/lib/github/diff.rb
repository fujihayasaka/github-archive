# typed: false
# frozen_string_literal: true

require "digest"
require "scientist"
require "set"

module GitHub
  # Git diff reading library that supports size-sensitive condensed diffs.
  #
  # GitHub::Diff provides an interface to diffs. diffstat information is
  # available for all files but full unified diff text is retrieved only for
  # files meeting the max_file, max_diff_size, and max_total_size limits.
  #
  # Use GitHub::Diff to generate a commit diff:
  #   repo = Repository.name_with_owner('rtomayko/git-sh')
  #   GitHub::Diff.new(repo, 'd2adbee...')
  #
  # Or a range diff between two commits:
  #   GitHub::Diff.new(repo, 'd3adb3e...', 'd3cafba...')
  #
  # diffstat information is available for the diff as a whole:
  #   diff = GitHub::Diff.new(repo, 'deadbee')
  #   p diff.summary.additions     # => 100
  #   p diff.summary.deletions     # => 101
  #   p diff.summary.changes       # => 201
  #   p diff.summary.changed_files # => 7
  #
  # You can also iterate over the files with stat and diff information:
  #   diffs = GitHub::Diff.new(repo, 'd3adb3e', 'd3cadba...')
  #   diffs.each do |entry|
  #     p entry.path       # => 'path/to/file.rb'
  #     p entry.status     # => 'M', 'A', 'D', 'C', 'R', or 'T'
  #     p entry.additions  # => 23
  #     p entry.deletions  # => 7
  #     p entry.changes    # => 30
  #     p entry.text       # => <unified diff text> or nil end
  class Diff
    autoload :ContextInjector, "github/diff/context_injector"
    autoload :Entry, "github/diff/entry"
    autoload :Enumerator, "github/diff/enumerator"
    autoload :Generator, "github/diff/generator"
    autoload :Line, "github/diff/line"
    autoload :Parser, "github/diff/parser"
    autoload :RelatedLinesEnumerator, "github/diff/related_lines_enumerator"
    autoload :SplitLinesEnumerator, "github/diff/split_lines_enumerator"
    autoload :Tree, "github/diff/tree"

    include Enumerable
    extend Forwardable
    include Scientist
    include GitHub::UTF8

    # Default values for diff loading limits
    DEFAULT_MAX_FILES       = 300
    DEFAULT_MAX_TOTAL_LINES = 20_000
    DEFAULT_MAX_TOTAL_SIZE  = 1 * 1024 * 1024  # 1M
    DEFAULT_MAX_DIFF_LINES  = 3_000
    DEFAULT_MAX_DIFF_SIZE   = 100 * 1024 # 100K

    # Assumed average size of a single diff line
    AVERAGE_LINE_SIZE = 40 # bytes

    # Top-only limits allow ~80% of all diffs GitHub renders on Dotcom
    # to be loaded without truncation. We use them for the initial
    # request of progressive diffs. See #apply_top_only_limits!
    TOP_ONLY_MAX_TOTAL_LINES = 400
    TOP_ONLY_MAX_TOTAL_SIZE  = 20 * 1024 # 20K (~ 50 bytes per line)
    TOP_ONLY_TIMEOUT         = 1 # second

    CONDENSED_DIFF_TIMEOUT_SECS   = 8

    # Auto-load limits are applied in a progressive diff batch request.
    #
    # The lower per-file limits avoid wasting processing time on large
    # diff entries that are of low value to the user.
    # See #apply_auto_load_single_entry_limits!
    #
    # The total limits apply across all batches a single diff can be
    # split up into. These total limits are never actually applied to
    # `condensed_diff` call, they are used to determine if additional
    # requests are necessary or not. See Diff::BatchedFileListView
    AUTO_LOAD_MAX_DIFF_LINES  = 400
    AUTO_LOAD_MAX_TOTAL_BYTES = TOP_ONLY_MAX_TOTAL_SIZE * 10
    AUTO_LOAD_MAX_TOTAL_LINES = TOP_ONLY_MAX_TOTAL_LINES * 10

    AlreadyLoaded = Class.new(StandardError)

    def self.max_diff_lines
      @max_diff_lines
    end

    def self.max_diff_lines=(val)
      @max_diff_lines = val
    end
    self.max_diff_lines = DEFAULT_MAX_DIFF_LINES

    def self.max_total_lines
      @max_total_lines
    end

    def self.max_total_lines=(val)
      @max_total_lines = val
    end
    self.max_total_lines = DEFAULT_MAX_TOTAL_LINES

    def self.default_timeout
      custom_default_timeout || CONDENSED_DIFF_TIMEOUT_SECS
    end

    def self.custom_default_timeout
      @custom_default_timeout
    end

    def self.custom_default_timeout=(val)
      @custom_default_timeout = val
    end

    # The Repository instance used to make git calls.
    attr_reader :repo

    # The SHA1 commit ids of the two versions to compare.
    attr_reader :sha2

    attr_accessor :base_sha

    # Maximum size of any one file's diff in bytes.
    # Default: See DEFAULT_MAX_DIFF_SIZE
    attr_accessor :max_diff_size

    # Maximum size of all diff output in bytes.
    # Default: See DEFAULT_MAX_TOTAL_SIZE
    attr_accessor :max_total_size

    # Maximum number of files to include full diff output for.
    # Default: See DEFAULT_MAX_FILES
    attr_accessor :max_files

    # Maximum number of lines in a single file's diff.
    # Default: See DEFAULT_MAX_DIFF_LINES
    attr_accessor :max_diff_lines

    # Maximum number of total lines in a diff (for all files).
    # Default: See DEFAULT_MAX_TOTAL_LINES
    attr_accessor :max_total_lines

    # Boolean indicating mode that sets limits to load only the beginning
    # of the diff. Default: false
    attr_accessor :top_only

    # Boolean indicating whether the summary is needed and therefore loaded.
    # Default: false
    attr_accessor :use_summary

    # The GitRPC::Client interface used for rpc interactions. Defaults to repo.rpc
    attr_accessor :rpc

    # Ignore whitespace when comparing lines. This ignores differences even if
    # one line has whitespace where the other line has none. Enables the -w
    # argument to git-diff.
    attr_accessor :ignore_whitespace
    alias ignore_whitespace? ignore_whitespace

    attr_accessor :context_lines

    # The amount of time the fileserver has to generate and read the diff. Any
    # diff that was read within this amount of time will be returned.
    def timeout=(value)
      @timeout = value
      timer.set_min_remaining(@timeout)
    end

    def timeout
      @timeout || self.class.default_timeout
    end

    def timer
      return @timer if defined?(@timer)
      @timer = GitHub::TimeoutCounter.new(timeout)
    end

    # Returns true if the diff had too many files
    def truncated_for_max_files?
      !!/^maximum file count exceeded/.match(truncated_reason)
    end

    # Returns true if the diff had too many lines
    def truncated_for_max_lines?
      !!/^maximum number of lines exceeded/.match(truncated_reason)
    end

    # Returns true if the diff had too many bytes
    def truncated_for_max_size?
      !!/^maximum diff size exceeded/.match(truncated_reason)
    end

    # Returns true if we only have partial diff output due to timeout
    def truncated_for_timeout?
      !!/^timeout reached/.match(truncated_reason)
    end

    # Create a new GitHub::Diff for a single commit or a range of commits.
    #
    # repo    - Repository object used to make git calls.
    # sha1    - 40 char SHA1 identifying the commit to use as the starting point.
    # sha2    - 40 char SHA1 identifying the commit to use as the ending point.
    # options - A hash of attribute options. All instance attributes defined
    #           above may be specified. In addition to the following:
    #           :paths         - List of paths to scope this diff to.
    #                            See #paths and #add_path.
    #           :delta_indexes - List of delta indexes to scope this diff to.
    #                            See #delta_indexes and #add_delta_index[es].
    #           :context_lines - A hash of file path Strings mapping to lists
    #                            of 1-indexed line ranges. Lines in the given
    #                            ranges are guaranteed to appear as context
    #                            lines in the diff entries even if they are
    #                            not in close proximity to an actual change.
    #           :head_repository - The head repository if it differs from repo.
    #           :base_repository - The base repository if it differs from repo.
    #
    def initialize(repo, sha1, sha2 = nil, options = {})
      raise TypeError if !repo.respond_to?(:rpc)
      options, sha2 = options.merge(sha2), nil if sha2.kind_of?(Hash)

      # default option values
      @ignore_whitespace = false
      @context_lines = nil

      # default diff selection values
      @max_files       = DEFAULT_MAX_FILES
      @max_diff_size   = DEFAULT_MAX_DIFF_SIZE
      @max_total_size  = DEFAULT_MAX_TOTAL_SIZE
      @max_diff_lines  = self.class.max_diff_lines
      @max_total_lines = self.class.max_total_lines
      @truncated       = false
      @paths           = Set.new(options.delete(:paths)).freeze
      @delta_indexes   = Set.new(options.delete(:delta_indexes)).freeze
      @top_only        = options.delete(:top_only) || false
      @use_summary     = options.delete(:use_summary) || false
      @head_repository = options.delete(:head_repository)
      @base_repository = options.delete(:base_repository)

      options.each { |k, v| send("#{k}=", v) }

      if sha2
        @sha1, @sha2 = sha1, sha2
      else
        @sha1, @sha2 = "#{sha1}^", sha1
      end

      @repo = repo

      @rpc ||= @repo.rpc

      apply_top_only_limits! if @top_only
    end

    # public: Instantiate a new diff without any path limitations or entries loaded
    #
    # This is useful if you need a duplicated diff but don't want it to be loaded already
    # so you can modify the paths. Primarily this is used for review comment positioning.
    def only_params
      options = {
        base_sha:          base_sha,
        ignore_whitespace: ignore_whitespace,
        max_diff_lines:    max_diff_lines,
        max_diff_size:     max_diff_size,
        max_files:         max_files,
        max_total_lines:   max_total_lines,
        max_total_size:    max_total_size,
        top_only:          top_only,
        use_summary:       use_summary,
        context_lines:     context_lines,
      }

      self.class.new(repo, sha1, sha2, options).tap do |diff|
        diff.summary = summary if summary_loaded?
      end
    end

    # Public: Set the per diff limits to be equal to the limits for the entire diff.
    #
    # When we are dealing with a single file such as viewing a single diff entry or positioning a
    # single comment, we only need a single diff entry so the limits grow to the size of the entire
    # diff.
    def maximize_single_entry_limits!
      self.max_diff_size  = DEFAULT_MAX_TOTAL_SIZE
      self.max_diff_lines = DEFAULT_MAX_TOTAL_LINES

      # Calling this method on a reduced diff (for example top only) can result
      # in the max total being less than the max for a single entry. This can
      # result in failure to position comments and makes no sense anyway.
      self.max_total_lines = max_diff_lines if max_total_lines < max_diff_lines
      self.max_total_size  = max_diff_size if max_total_size < max_diff_size
    end

    def record_diff_metrics(summary: false, params: {}, dogstats_request_tags: [])
      if @repo.feature_enabled?(:diff_new_distribution_metrics)
        record_diff_metrics_to_dogstats(tags: dogstats_request_tags)
        record_diff_summary_metrics(tags: dogstats_request_tags) if summary
      end

      result = case
      when truncated_for_max_files?
        "truncated.max_files"
      when truncated_for_max_lines?
        "truncated.max_lines"
      when truncated_for_max_size?
        "truncated.max_size"
      when truncated_for_timeout?
        "truncated.timeout"
      when timed_out?
        "error.timeout"
      when too_busy?
        "error.too_busy"
      when corrupt?
        "error.corrupt"
      when missing_commits?
        "error.missing_commits"
      end

      tags = ["action:render", "type:#{params[:action].parameterize}", "controller:#{params[:controller].parameterize}"]
      tags << "result:#{result}" if result

      GitHub.dogstats.increment("diff", tags: tags)

      too_many_lines_count = 0
      too_many_bytes_count = 0
      entries.each do |entry|
        case
        when entry.skipped_for_max_lines?
          too_many_lines_count += 1
        when entry.skipped_for_max_size?
          too_many_bytes_count += 1
        end
      end

      if too_many_lines_count > 0
        GitHub.dogstats.distribution("diff.file_skipped", too_many_lines_count, tags: tags + ["result:max_lines"])
      end

      if too_many_bytes_count > 0
        GitHub.dogstats.distribution("diff.file_skipped", too_many_bytes_count, tags: tags + ["result:max_size"])
      end

      limited_files_count = too_many_lines_count + too_many_bytes_count
      if limited_files_count > 0
        GitHub.dogstats.distribution("diff.file_skipped", limited_files_count, tags: tags + ["result:limited_files"])
      end
    end

    # Public: Set the total limits to be equal to the per diff limits.
    #
    # This is the opposite of #maximize_single_entry_limits!
    def minimize_total_limits!
      self.max_total_size  = DEFAULT_MAX_DIFF_SIZE
      self.max_total_lines = DEFAULT_MAX_DIFF_LINES
    end

    # Public: Constructs a tree structure of the changed files
    def to_tree(flatten_fileless_directories: true)
      Tree.build(self, flatten_fileless_directories: flatten_fileless_directories)
    end

    alias_method :top_only?, :top_only
    alias_method :use_summary?, :use_summary

    # Total number of entries
    #
    # Returns Integer
    def size
      @corrupt ? 0 : cache("size") { entries.size }
    end

    def empty?
      changed_files <= 0
    end
    alias_method :blank?, :empty?

    def any?
      available? && !empty?
    end

    # Reader for @sha1, normalizes NULL_OIDs
    def sha1
      if @sha1 == ::GitRPC::NULL_OID
        nil
      else
        @sha1
      end
    end

    # Retrieve and iterate over diff objects for all changed files
    # in pathname order. Unified diff text may be excluded according to the
    # rules for selecting diffs.
    def each(&bk)
      entries.each(&bk)
    end

    # Retrieve a diff object by its index position or path name.
    #
    # index - A numeric index position or string diff filename to retrieve.
    #
    # Returns a ChangedFile for the given index when found, or nil
    # when no diff exists at that path.
    #
    # Raises TypeError when the index argument is invalid.
    def [](index)
      case index
      when Numeric
        entries[index]
      when String
        with_path(index)
      else
        raise TypeError, "Numeric or String expected for #{index.inspect}"
      end
    end

    # Public: List of paths to scope this diff to
    #
    # Returns Array of Strings
    def paths
      @paths.to_a.freeze
    end

    # Public: List of file types included in this diff deltas
    #
    # Returns Array of Strings
    def file_types
      return @file_types if defined?(@file_types)
      @file_types = deltas.map { |delta| get_file_type(delta.new_file.path || delta.old_file.path) }.compact.uniq
    end

    # Public: List of filenames included in this diff's deltas. If a file
    # has been renamed, its new filename will be included, and not its old
    # filename.
    #
    # Returns Array of Strings
    def filenames
      return @filenames if defined?(@filenames)
      @filenames = deltas.map { |delta| delta.new_file.path || delta.old_file.path }.compact.map(&File.method(:basename)).uniq
    end

    DOTFILE_REGEX = %r{\A[.]}

    def get_file_type(path)
      return if path.blank?

      file_type = File.extname(path)
      return utf8(file_type) if file_type.present?

      basename = File.basename(path)
      dotfile = DOTFILE_REGEX.match(utf8(basename))
      return "dotfile" if dotfile

      "No extension"
    end

    # Public: Add paths to the diff's set of examined paths if it exists in the ToC.
    #
    # paths - Array of paths to add to the diff's paths
    # side  - the side of the diff on which the path should be present. must be one of:
    #         :a (left), :b (right), nil (either). Defaults to either.
    #
    # Returns nothing
    def add_paths(new_paths, side: nil)
      raise ArgumentError, "Side must be :a, :b, or nil" unless [:a, :b, nil].include?(side)

      @paths = new_paths.each_with_object(@paths.dup) do |new_path, paths|
        next if new_path.nil?

        # convert unicode paths to raw so we can match paths from deltas
        new_path = new_path.b

        next if paths.include?(new_path)

        # we don't already have this path so if the diff is already loaded, it is too late
        raise AlreadyLoaded if loaded?

        if delta = delta_for_path(new_path, side: side)
          paths.merge(delta.paths)
        else
          paths << new_path
        end
      end

      @paths.freeze

      reset_requested_deltas
    end

    # Public: Add the path to the diff's set of examined paths if it exists in the ToC.
    #
    # path - the path to add to the diff's paths
    # side - the side of the diff on which the path should be present. must be one of:
    #        :a (left), :b (right), nil (either). Defaults to either.
    #
    # Returns nothing
    def add_path(path, side: nil)
      add_paths([path], side: side)
    end

    # Public: Find the GitRPC::Diff::Delta object for the given path
    #
    # path - the path for the delta in which you are interested.
    # side - limit the search to either the :a or :b side of the delta. Defaults to either (nil)
    #
    # Returns the delta object or nil if it cannot be found.
    def delta_for_path(path, side: nil)
      delta = deltas.detect { |e| e.new_file.path == path } if side.nil? || side == :b
      return delta unless delta.nil?

      deltas.detect { |e| e.old_file.path == path } if side == :a || side.nil?
    end

    # Public: Array of delta indexes to scope this diff to
    #
    # Returns an Array of Integers
    def delta_indexes
      @delta_indexes.to_a.freeze
    end

    # Public: Add list of delta indexes
    #
    # indexes - Array of Integers
    #
    # Returns nothing
    def add_delta_indexes(indexes)
      raise AlreadyLoaded if loaded?

      unless indexes.all? { |index| index.is_a?(Integer) }
        raise TypeError, "Some indexes are not Integers"
      end

      indexes.reject!(&:negative?)
      @delta_indexes += Set.new(indexes)
      @delta_indexes.freeze

      reset_requested_deltas
    end

    # Public: Add a single delta index
    #
    # index - Integer
    #
    # Returns nothing
    def add_delta_index(index)
      add_delta_indexes([index])
    end

    # Public: List of deltas that are requested with this diff
    #
    # Returns an Array of GitRPC::Diff::Deltas or GitRPC::Diff::Summary::Deltas
    def requested_deltas
      return @requested_deltas unless @requested_deltas.nil?
      return @requested_deltas = deltas.dup if paths.empty? && delta_indexes.empty?

      selected_deltas = []

      # TODO: Once all paths are added via add_path, this step will become unnecessary
      unless paths.empty?
        @paths = Set.new(paths.map { |path| path.try(:b) }).freeze
      end

      unless paths.empty?
        deltas_from_paths = deltas.select { |e| paths.include?(e.old_file.path) }
        selected_deltas.concat(deltas_from_paths)
      end

      unless delta_indexes.empty?
        deltas_from_indices = deltas.values_at(*delta_indexes).compact
        selected_deltas.concat(deltas_from_indices)
      end

      @requested_deltas = selected_deltas.uniq
    end

    # Internal: Resets the list of requested deltas to ensure they get recomputed
    #
    # Returns nothing
    def reset_requested_deltas
      @requested_deltas = nil
    end

    # Public: List of requested paths
    #
    # Returns an Array of Strings
    def requested_paths
      requested_deltas.flat_map(&:paths).uniq
    end

    # Public: Lists the paths that have been loaded by this diff. Excludes truncated entries.
    #
    # Returns an array of the String paths of entries loaded by the diff. In the case of renames, both paths
    # are included.
    def non_truncated_paths
      return @non_truncated_paths if defined?(@non_truncated_paths)

      if !loaded?
        GitHub.dogstats.increment("diff.non_truncated_paths_not_loaded")
        return []
      end

      non_truncated = entries.reject { |e| e.truncated? }

      @non_truncated_paths = non_truncated.flat_map { |e| [e.a_path_raw, e.b_path_raw].compact }.uniq
    end

    # Locate a diff for a given path name. This first checks for an exact match on
    # b_path names and then falls back on looking for renamed files.
    #
    # path - String full path name to file.
    #
    # Returns a GitHub::Diff::Entry object for the diff.
    def with_path(path)
      entries.each do |entry|
        if entry.path == path
          return entry
        elsif entry.path > path
          break  # diffs are sorted by path name
        end
      end
      entries.find { |entry| entry.renamed? && entry.a_path == path }
    end

    # Public: The stats on this diff
    #
    # Returns a GitRPC::Diff::Summary
    def summary
      return @summary if defined?(@summary)

      @summary = timer.update do
        repo.read_diff_summary(parsed_sha1, parsed_sha2, base_sha,
          commit1_repo: @base_repository, commit2_repo: @head_repository,
          timeout: timer.remaining, algorithm: git_diff_algorithm)
      end
    end
    attr_writer :summary

    # Internal: Was the diff's summary loaded?
    #
    # Returns a Boolean
    def summary_loaded?
      defined?(@summary)
    end

    # Is the summary cached?
    def summary_warm?
      repo.diff_summary_cached?(parsed_sha1, parsed_sha2, base_sha, algorithm: git_diff_algorithm)
    end

    def inject_context_lines?
      context_lines&.values&.any?(&:present?)
    end

    # Public: A complete list of all deltas
    #
    # Returns an Array of GitRPC::Diff::Deltas or GitRPC::Diff::Summary::Deltas
    def deltas
      return @deltas if defined?(@deltas)

      @deltas = if summary_loaded? || use_summary?
        summary.deltas
      else
        load_deltas
      end
    end

    # Internal: Loads the diffs deltas
    #
    # Returns an Array of GitRPC::Diff::Deltas
    def load_deltas
      timer.update do
        rpc.native_read_diff_toc(parsed_sha1, parsed_sha2, base_sha,
                                 "timeout" => timer.remaining)
      end
    end

    def_delegators :summary, :changes, :additions, :deletions

    # Total number of changed files
    #
    # Returns Integer
    def changed_files
      return @changed_files if defined?(@changed_files)

      @changed_files = if summary_loaded? || use_summary?
        GitHub.dogstats.increment("diff.changed_files", tags: ["overlimit:false", "from_summary:true"])
        summary.changed_files
      elsif deltas.size >= GitRPC::Diff::DiffTreeParser::MAX_FILES
        GitHub.dogstats.increment("diff.changed_files", tags: ["overlimit:true", "from_summary:true"])
        summary.changed_files
      else
        GitHub.dogstats.increment("diff.changed_files", tags: ["overlimit:false", "from_summary:false"])
        deltas.size
      end
    end

    def too_big?
      changed_files > max_files
    end

    # Have the diff's entries been loaded? If not, some operations could result in a costly gitrpc call
    def loaded?
      !!defined?(@entries_hash)
    end

    def total_line_count
      entries.map(&:line_count).sum
    end

    def total_byte_count
      entries.map(&:byte_count).sum
    end

    def truncated?
      self.truncated
    end

    def truncated
      entries_hash["truncated"]
    end

    def truncated_reason
      entries_hash["truncated_reason"]
    end

    def entries_cached?
      cached?("entries_hash")
    end

    def entries
      entries_hash["entries"]
    end

    alias to_a entries

    def entries_hash
      return @entries_hash if defined? @entries_hash

      @entries_hash = load_entries_hash
    end

    def entries_hash_cache_key
      cache_prefix(:toc_entries_hash)
    end

    def load_entries_hash
      start_time = Time.now
      cached = true

      entries_hash = GitHub.cache.fetch(entries_hash_cache_key, stats_key: "diff.cache.toc_entries_hash") do
        cached = false
        load_entries_hash!
      end

      if cached && use_summary? && !entries_hash["truncated"]
        entries_changes = entries_hash["entries"].collect(&:changes).sum
        delta_changes = deltas.reject(&:binary?).collect(&:changes).sum
        if entries_changes == 0 && delta_changes > 0
          # If the cached entries are empty but we expected changes (deltas/summary are never cached),
          # then we should reload the diff and refresh the cache.
          GitHub.dogstats.increment("diff.refresh_cached_entries")

          cached = false
          entries_hash = load_entries_hash!
          GitHub.cache.write(entries_hash_cache_key, entries_hash, stats_key: "diff.cache.toc_entries_hash")
        end
      end

      duration_ms = (Time.now - start_time) * 1000
      GitHub.dogstats.timing "diff.load", duration_ms, tags: %W(cached:#{cached})

      entries_hash
    end

    # Internal: Retrieves the diff patches (entries) using diff-pairs
    # by passing in the requested deltas.
    #
    # Returns Hash
    def load_entries_hash!
      truncated_deltas = requested_deltas[0, max_files]

      indexed_deltas = {}
      truncated_deltas.each do |delta|
        # TODO: Key generation for entries and deltas should be extracted into a single method
        key = [delta.old_file.path, delta.status, delta.new_file.path].join(":")

        indexed_deltas[key] = delta
      end

      result = if truncated_deltas.empty?
        { "data" => "" }
      else
        entries_timeout = if top_only?
          [TOP_ONLY_TIMEOUT, timer.remaining].min
        else
          timer.remaining
        end

        timer.update do
          load_diff_pairs(truncated_deltas, entries_timeout)
        end
      end

      text_entries = {}

      parser = if inject_context_lines?
        GitHub.dogstats.distribution("checks.injected_context_line_count", context_lines.count)
        GitHub.dogstats.time "checks.inject_context_lines.time" do
          context_injector = GitHub::Diff::ContextInjector.new(
            diff_text: result["data"],
            context_lines: context_lines,
            sha2: @sha2,
            rpc: @rpc,
            repo: @repo,
          )
          Parser.new(context_injector.expanded_diff)
        end
      else
        Parser.new(result["data"])
      end

      parser.each do |entry|
        # TODO: Key generation for entries and deltas should be extracted into a single method
        key = [entry.a_path_raw || entry.b_path_raw, entry.status, entry.b_path_raw || entry.a_path_raw].join(":")

        # TODO: Long-term refactoring => Pass delta to entry and
        # delegate all data accessors to the delta. This way we could
        # drop this if-clause.
        if entry.renamed? && entry.b_blob.nil?
          delta = indexed_deltas[key]
          entry.b_blob = delta.new_file.oid if delta
          entry.a_mode = delta.old_file.mode if delta
          entry.b_mode = delta.new_file.mode if delta
        end

        entry.whitespace_ignored = ignore_whitespace
        entry.a_sha = parsed_sha1
        entry.b_sha = parsed_sha2
        entry.context_lines = context_lines[entry.path] if context_lines

        text_entries[key] = entry
      end

      truncated_for_max_files = requested_deltas.size > max_files

      truncated = parser.truncated || truncated_for_max_files
      truncated_reason = parser.truncated_reason
      truncated_reason ||= "timeout reached." if result["timed_out"]
      truncated_reason ||= "unknown reason." if parser.truncated

      fresh_entries = []

      deltas_to_process = indexed_deltas.dup

      # Fill in entries with text and whitespace-only changes
      while deltas_to_process.any?
        key, delta = deltas_to_process.shift

        if text_entries.has_key?(key)
          fresh_entries << text_entries.delete(key)
          break if text_entries.empty?
        else
          # Create diff entry for files with whitespace-only changes
          fresh_entries << GitHub::Diff::Entry.from(diff: self, delta: delta)
        end
      end

      # Fill in entries without text
      while deltas_to_process.any?
        key, delta = deltas_to_process.shift

        fresh_entries << GitHub::Diff::Entry.from(diff: self, delta: delta).tap do |entry|
          # These entries are marked truncated since they were not part
          # of the entries returned by diff-pairs.
          entry.truncated_reason = truncated_reason
        end
      end

      fresh_entries.sort_by!(&:path)

      if truncated_for_max_files && !result["timed_out"]
        truncated_reason = "maximum file count exceeded: total=#{requested_deltas.size}"
      end

      {
        "entries" => fresh_entries,
        "truncated" => truncated,
        "truncated_reason" => truncated_reason,
      }
    end

    def parsed_sha1
      return @parsed_sha1 if defined?(@parsed_sha1)
      @parsed_sha1 = sha1 ? repo.rev_parse(sha1) : nil
    end

    def parsed_sha2
      return @parsed_sha2 if defined?(@parsed_sha2)
      @parsed_sha2 = sha2 ? repo.rev_parse(sha2) : nil
    end

    # Git diff compatible algorithm
    def git_diff_algorithm
      if ignore_whitespace
        "ignore-whitespace"
      else
        "vanilla"
      end
    end

    alias algorithm git_diff_algorithm

    def load_diff_pairs(truncated_deltas, entries_timeout)
      options = {
        "max_diff_size" => @max_diff_size,
        "max_total_size" => @max_total_size,
        "max_diff_lines" => @max_diff_lines,
        "max_total_lines" => @max_total_lines,
        "ignore_whitespace" => ignore_whitespace,
        "max_files" => @max_files,
        "timeout" => entries_timeout,
      }

      rpc.read_diff_pairs_with_base(
        parsed_sha1, parsed_sha2, base_sha,
        truncated_deltas, options
      )
    end

    def load_diff(timeout: self.class.default_timeout)
      new_timeout = [self.timeout, timeout].compact.min
      self.timeout = new_timeout

      available?
    end

    # Is the diff available?
    #
    # It's possible for the diff to be unavailable due to:
    #   * "corrupt"         - Something unexpected happened. Possibly a corrupt repository.
    #   * "missing commits" - The base or head commit don't exist in this repository. This can happen
    #                         if a commit is looked up through the wrong repository in a public network,
    #                         but the lookup succeeds because the commit was in the shared commit cache.
    #   * "timeout"         - The diff took too long to generate
    #   * "too busy"        - The fileserver is under heavy load and the condense-diff
    #                         process was killed by gitmon
    #
    # The entries array will be empty when unavailable.
    #
    # Returns false if the diff is available, or the reason that the diff is not available otherwise.
    def unavailable_reason
      return @unavailable_reason if defined?(@unavailable_reason)
      cache_key = cache_prefix("unavailable_reason")

      if @unavailable_reason = GitHub.cache.get(cache_key)
        @entries_hash = {
          "entries" => [],
          "truncated" => false,
          "truncated_reason" => nil,
        }
      elsif @unavailable_reason = unavailable_reason!
        GitHub.cache.set(cache_key, @unavailable_reason, 5.minutes.to_i) unless ["too busy", "missing commits"].include?(@unavailable_reason)
        @entries_hash = {
          "entries" => [],
          "truncated" => false,
          "truncated_reason" => nil,
        }
      end

      @unavailable_reason
    end

    # the actual exception that occurred causing the diff to be unavailable
    attr_accessor :unavailable_error

    # Internal: Perform the actual availability check without memoization or caching.
    #
    # Returns an error message if the diff is corrupt or times out, false otherwise.
    def unavailable_reason!
      return "corrupt" if [sha1, sha2].include?(GitHub::NULL_OID)
      return false if defined?(@entries_hash)

      return summary_unavailable_reason! if use_summary?

      entries

      false
    rescue GitRPC::Error, GitHub::Diff::Parser::UnrecognizedText => e
      self.unavailable_error = e
      case e
      when GitRPC::Timeout then "timeout"
      when GitRPC::CommandBusy then "too busy"
      when GitRPC::ObjectMissing then "missing commits"
      when GitRPC::InvalidRepository then "corrupt"
      else
        Failbot.report(e)
        "corrupt"
      end
    end

    def summary_unavailable_reason!
      if !summary.available?
        self.unavailable_error = summary.unavailable_error
        summary.unavailable_reason
      else
        false
      end
    end

    def available?
      unavailable_reason == false
    end

    def timed_out?
      unavailable_reason == "timeout"
    end

    def too_busy?
      unavailable_reason == "too busy"
    end

    def corrupt?
      unavailable_reason == "corrupt"
    end

    def missing_commits?
      unavailable_reason == "missing commits"
    end

    ##
    # Internals

    def apply_top_only_limits!
      self.max_total_lines = TOP_ONLY_MAX_TOTAL_LINES
      self.max_total_size  = TOP_ONLY_MAX_TOTAL_SIZE
    end

    # Internal: Apply the auto-load limits for a single diff entry.
    #
    # Depending on the number of changed files, we adjust the max diff entry
    # limits proportionally within the limits of DEFAULT_MAX_DIFF_LINES and
    # AUTO_LOAD_MAX_DIFF_LINES.
    #
    # Notice: This might trigger the diff summary to load, see #changed_files.
    #
    # Returns nothing
    def apply_auto_load_single_entry_limits!
      lines = if empty?
        AUTO_LOAD_MAX_DIFF_LINES
      else
        custom_max_diff_lines = DEFAULT_MAX_DIFF_LINES / changed_files
        [custom_max_diff_lines, AUTO_LOAD_MAX_DIFF_LINES].max
      end
      size = lines * AVERAGE_LINE_SIZE

      # FIXME: on top_only requests we want the diff to be truncated so that we
      # attempt a follow up request with bigger limits. Potentially having a
      # max_diff_size that is greater than max_total_size will allow for this.
      # On batch requests this doesn't make sense, we just want the diff to
      # always be skipped.
      # This is an ugly solution, all limits should be dynamic and additional
      # requests should not be made. Please fix this.
      unless top_only?
        lines = [lines, self.max_total_lines].min
        size = [size, self.max_total_size].min
      end

      self.max_diff_lines = lines
      self.max_diff_size  = size
    end

    # Public: find the position (diff offset) in the diff entry for the given comment.
    #
    # blob_position - Integer or nil adjusted position.
    # path          - The String path for the position
    # left_side     - The side of the diff corresponding to this line
    #
    # Returns the Integer position in the Diff being viewed for this line.
    def position_for(blob_position, path, left_side)
      return unless entry = self[path]
      entry.position_for(blob_position, left_side)
    end

    def cached?(key)
      GitHub.cache.exist?(cache_prefix(key))
    end

    def cache(key, &block)
      if (value = instance_variable_get("@#{key}")).nil?
        value = GitHub.cache.fetch(cache_prefix(key), stats_key: "diff.cache.#{key}") { yield }
        instance_variable_set("@#{key}", value)
      end
      value
    end

    def cache_prefix(key)
      @prefix ||= begin
        # `repo_digest` is a cache component that includes the identity of
        # the RPC and any alternates that it has been extended with.
        # This prevents inadvertent use of a cache entry that was written for a
        # different repository, or use of a cache entry that was
        # generated with extended alternates when reading for a repo
        # that was not extended in the same way.
        repo_digest = Digest::SHA256.new
        repo_digest << rpc.repository_cache_key # *identity* of the repo, not its contents or state.
        if rpc.options[:alternates]
          rpc.options[:alternates].sort.each do |alt_path|
            repo_digest << alt_path
          end
        end
        paths_key = Digest::SHA256.hexdigest(paths.join(":")) if paths.any?
        delta_indexes_key = Digest::SHA256.hexdigest(delta_indexes.join(":")) if delta_indexes.any?
        if inject_context_lines?
          digest = Digest::SHA256.new
          context_lines.keys.sort.each do |path|
            digest << path << ": "
            digest << sort_ranges(context_lines[path]).inspect << " "
          end
          context_lines_key = digest.hexdigest
        end

        [
          "GitHub::Diff", "v15", repo_digest.hexdigest, sha1, sha2, base_sha,
          git_diff_algorithm,
          paths_key, delta_indexes_key,
          max_diff_lines, max_total_lines,
          context_lines_key,
          "prog_output"
        ].compact.join(":")
      end

      "#{@prefix}:#{key}"
    end

    def sort_ranges(ranges)
      ranges.sort do |a, b|
        result = a.first <=> b.first
        if result != 0
          result
        else
          a.last <=> b.last
        end
      end
    end

    private

    # Private: We use dogstats for new metrics
    #
    # Returns nothing
    def record_diff_metrics_to_dogstats(tags: [])
      prefix = "diff.render.dist"

      GitHub.dogstats.distribution("#{prefix}.files", size, tags:)
      GitHub.dogstats.distribution("#{prefix}.lines", total_line_count, tags:)
      GitHub.dogstats.distribution("#{prefix}.bytes", total_byte_count, tags:)

      entries.each do |entry|
        GitHub.dogstats.distribution("#{prefix}.per_file.lines", entry.line_count, tags:)
        GitHub.dogstats.distribution("#{prefix}.per_file.bytes", entry.byte_count, tags:)
      end
    end

    def record_diff_summary_metrics(tags: [])
      prefix = "diff.render.summary.dist"

      GitHub.dogstats.distribution("#{prefix}.files", changed_files, tags:)
      GitHub.dogstats.distribution("#{prefix}.changes", changes, tags:)
    end
  end
end
