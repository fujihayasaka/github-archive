# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Contents
  class Loader
    include DiffLineChangeMarker

    MAXIMIZE_SINGLE_ENTRY_LIMIT_THRESHOLD = 1

    class DiffLine < T::Struct
      const :display_no_new_line_warning, T::Boolean
      # can be plain text, plain HTML with intra-line changes, or syntax highlighted HTML
      const :html, String
      const :left, T.nilable(Integer)
      const :line_number, Integer
      const :position, Integer
      const :right, T.nilable(Integer)
      const :text, String
      const :type, String
    end

    class DiffContent < T::Struct
      const :binary_size, T.nilable(Integer)
      const :diff_entry, GitHub::Diff::Entry
      const :diff_index, Integer
      const :lines, T::Array[DiffLine]
      const :new_tree_entry, T.nilable(TreeEntry)
      const :old_tree_entry, T.nilable(TreeEntry)
      const :reviewed, T::Boolean
    end

    class Data < T::Struct
      const :before_commit_oid, String
      const :after_commit_oid, String
      const :diffs, T::Array[DiffContent]
    end

    sig do
      params(
        diff: GitHub::Diff,
        ignore_whitespace: T::Boolean,
        timeout: T.any(Integer, Float),
        top_only: T::Boolean,
        viewed_files: PullRequestUserReviews,
        paths: T::Array[String],
        repository: T.nilable(Repository),
        context_lines: T.nilable(T::Hash[String, T::Array[T::Range[Integer]]]),
      ).returns(Data)
    end
    def self.load(diff:, ignore_whitespace:, timeout:, top_only:,  viewed_files:, paths: [], repository: nil, context_lines: nil)
      new(diff:, ignore_whitespace:, timeout:, top_only:, paths:, repository:, context_lines:, viewed_files:).load
    end

    sig do
      params(
        diff: GitHub::Diff,
        ignore_whitespace: T::Boolean,
        timeout: T.any(Integer, Float),
        top_only: T::Boolean,
        viewed_files: PullRequestUserReviews,
        repository: T.nilable(Repository),
        context_lines: T.nilable(T::Hash[String, T::Array[T::Range[Integer]]]),
        paths: T::Array[String],
      ).void
    end
    def initialize(diff:, ignore_whitespace:, timeout:, top_only:, viewed_files:, repository:, context_lines: nil, paths: [])
      @diff = diff
      @ignore_whitespace = ignore_whitespace
      @paths = paths
      @repository = repository
      @timeout = timeout
      @top_only = top_only
      @context_lines = context_lines
      @viewed_files = viewed_files
    end

    sig { returns(Data) }
    def load
      # Diff paths cannot be updated if the diff entries have already been loaded.
      begin
        @diff.add_paths(@paths) unless @paths.empty?
      rescue GitHub::Diff::AlreadyLoaded => error
        raise error unless Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        GitHub.logger.error(
          "Unable to add paths to loaded diff", {
          "exception.type": error.class,
          "gh.catalog_service": "github/pull_requests",
          "gh.repo.name_with_owner": T.must(@repository).name_with_display_owner,
          "gh.repo.id": T.must(@repository).id,
        })
        Failbot.report(error)
      end

      @diff.use_summary = true
      @diff.timeout = @timeout
      @diff.ignore_whitespace = @ignore_whitespace
      @diff.top_only = @top_only
      @diff.context_lines = @context_lines if @context_lines

      # We need to set diff entry size limits before loading the diff entries.
      set_single_entry_limits(@diff, @paths, @top_only)

      @diff.load_diff

      diff_entries = T.let([], T::Array[GitHub::Diff::Entry])
      content_tree_entries = T.let([], T::Array[TreeEntry])
      diff_entries_with_content_lookup = T.let({}, T::Hash[String, GitHub::Diff::Entry])

      @diff.entries.each do |diff_entry|
        diff_entries << diff_entry

        tree_entry = diff_entry_blob(diff_entry, @repository)

        # Determine which entries have content so we can prefill
        if has_content?(diff_entry, tree_entry)
          content_tree_entries << tree_entry unless tree_entry.nil?
          diff_entries_with_content_lookup[diff_entry.path_digest] = diff_entry
        end
      end

      # Prefill attributes and line counts
      TreeEntry.load_attributes!(content_tree_entries, @diff.sha2)
      TreeEntry.load_line_counts!(@repository, content_tree_entries)
      binary_sizes = prepare_binary_sizes(@repository, diff_entries)

      # Warm up the syntax highlighting cache, only highlighting lines with content
      highlighted_diff = SyntaxHighlightedDiff.new(@repository)
      highlighted_diff.highlight!(diff_entries_with_content_lookup.values)

      diffs = diff_entries.map.with_index do |diff_entry, i|
        lines = if diff_entries_with_content_lookup.key?(diff_entry.path_digest)
          syntax_highlighted_lines = highlighted_diff.colorized_lines(diff_entry)&.freeze
          syntax_highlighted_lines&.each(&:freeze)

          diff_lines(diff_entry, syntax_highlighted_lines)
        else
          []
        end

        # Reuse the same TreeEntry objects so we don't lose prefilled attributes
        new_tree_entry = content_tree_entries.find { |entry| entry.path == diff_entry.b_path } unless diff_entry.deleted?
        old_tree_entry = content_tree_entries.find { |entry| entry.path == diff_entry.a_path } if diff_entry.deleted?

        DiffContent.new(
          binary_size: binary_size(binary_sizes, diff_entry),
          diff_entry: diff_entry,
          diff_index: i,
          lines: lines,
          new_tree_entry: new_tree_entry.nil? ? new_tree_entry(diff_entry, @repository) : new_tree_entry,
          old_tree_entry: old_tree_entry.nil? ? old_tree_entry(diff_entry, @repository) : old_tree_entry,
          reviewed: @viewed_files.reviewed?(diff_entry.path),
        )
      end

      Data.new(
        before_commit_oid: @diff.sha1,
        after_commit_oid: @diff.sha2,
        diffs: diffs,
      )
    end

    private

    # Single entry size limits are based the `top_only` option or the number of changed files. We can determine the
    # changed files count via the `paths` option, or if the diff summary or diff deltas are already loaded, via
    # GitHub::Diff#changed_files. Calling changed_files will trigger a GitRPC call unless the summary or deltas are
    # loaded, which we want to avoid, so check first and fallback to auto-load limits if both are unloaded.
    sig do
      params(
        diff: GitHub::Diff,
        paths: T::Array[String],
        top_only: T::Boolean,
      ).void
    end
    def set_single_entry_limits(diff, paths, top_only)
      if top_only
        diff.apply_top_only_limits!
        return
      end

      changed_files_count = \
        if !paths.empty?
          paths.length
        elsif diff.summary_loaded? || diff.deltas_loaded?
          diff.changed_files
        else
          # undeterminable
        end

      if changed_files_count == MAXIMIZE_SINGLE_ENTRY_LIMIT_THRESHOLD
        diff.maximize_single_entry_limits!
      else
        diff.apply_auto_load_single_entry_limits!
      end
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        repository: T.nilable(Repository)
      ).returns(T.nilable(TreeEntry))
    end
    def diff_entry_blob(diff_entry, repository = nil)
      if diff_entry.deleted?
        old_tree_entry(diff_entry, repository)
      else
        new_tree_entry(diff_entry, repository)
      end
    end

    sig { params(entry: GitHub::Diff::Entry, repository: T.nilable(Repository)).returns(T.nilable(TreeEntry)) }
    def new_tree_entry(entry, repository)
      return nil if entry.deleted?

      TreeEntry.new(repository, {
        "path" => entry.b_path || "", "mode" => entry.b_mode, "oid" => entry.b_blob, "type" => "blob"
      })
    end

    sig { params(entry: GitHub::Diff::Entry, repository: T.nilable(Repository)).returns(T.nilable(TreeEntry)) }
    def old_tree_entry(entry, repository)
      return nil if entry.added?

      TreeEntry.new(repository, {
        "path" => entry.a_path || "", "mode" => entry.a_mode, "oid" => entry.a_blob, "type" => "blob"
      })
    end

    sig { params(repository: T.nilable(Repository), entries: T::Array[GitHub::Diff::Entry]).returns(T::Hash[String, Integer]) }
    def prepare_binary_sizes(repository, entries)
      binary_sizes = {}
      oids = []

      entries.each do |diff|
        oids << diff.a_blob << diff.b_blob if diff.binary?
      end

      oids.compact!
      oids.uniq!

      if oids.any? && repository
        headers = repository.rpc.read_object_headers(oids)

        headers.each_with_index do |obj_header, i|
          oid = oids[i]
          binary_sizes[oid] = obj_header["size"]
        end
      end

      binary_sizes
    end

    sig do
      params(
        blob_sizes: T::Hash[String, Integer],
        diff: GitHub::Diff::Entry
      ).returns(T.nilable(Integer))
    end
    def binary_size(blob_sizes, diff)
      return nil unless diff.binary?

      base_blob_size = blob_sizes[diff.a_blob]
      head_blob_size = blob_sizes[diff.b_blob]

      diff_size = if diff.modified?
        (head_blob_size || 0) - (base_blob_size || 0)
      else
        base_blob_size || 0
      end
    end

    sig { params(diff_entry: GitHub::Diff::Entry, syntax_highlighted_diff: T.nilable(T::Array[String])).returns(T::Array[DiffLine]) }
    def diff_lines(diff_entry, syntax_highlighted_diff)
      show_no_newline_warning = valid_no_new_line_file?(diff_entry.path)

      diff_entry.enumerator.map do |line|
        line = T.let(line, GitHub::Diff::Line)

        if syntax_highlighted_diff
          html = syntax_highlighted_diff[line.position]
          related_html = line.related_line ? syntax_highlighted_diff[line.related_line.position] : nil
          html = mark_intra_line_changes_html(line, html, related_html)
        else
          html = line.related_line ? mark_intra_line_changes(line) : line.text
        end

        html = ERB::Util.h(html)
        html.chomp!
        html.gsub!("\r", "")
        html = "<br>" unless html.present?

        DiffLine.new(
           type: line.type.to_s.upcase,
           line_number: line.current,
           text: line.text,
           display_no_new_line_warning: show_no_newline_warning && line.nonewline?,
           position: line.position,
           html: html,
           left: line.left == -1 ? nil : line.left,
           right: line.right == -1 ? nil : line.right,
         )
      end
    end

    # path - a filename with the extension
    #
    # We only show the no new line warning on certain languages.
    # This method will return true when the language is not in the list.
    sig { params(path: String).returns(T::Boolean) }
    def valid_no_new_line_file?(path)
      languages = Linguist::Language.find_by_filename(path)
      languages = Linguist::Language.find_by_extension(path) if languages.empty?

      !languages.any? { |lang| lang.wrap }
    end

    sig { params(diff_entry: GitHub::Diff::Entry, tree_entry: T.nilable(TreeEntry)).returns(T::Boolean) }
    def has_content?(diff_entry, tree_entry)
      return false if tree_entry.nil?

      diff_is_hidden = diff_entry.too_big? || diff_entry.deleted? || tree_entry.generated?

      !diff_is_hidden && !diff_entry.text.blank?
    end
  end
end
