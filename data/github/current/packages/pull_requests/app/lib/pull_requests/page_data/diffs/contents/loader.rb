# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Contents
  class Loader
    include DiffLineChangeMarker
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry
    include PullRequests::PageData::Diffs::Contents::AmbiguousCharacterDetection

    MAXIMIZE_SINGLE_ENTRY_LIMIT_THRESHOLD = 1

    ContextLines = T.type_alias { T.nilable(T::Hash[String, T::Array[T::Range[Integer]]]) }

    class HighlightStrategy < T::Enum
      enums do
        ServerGenerated = new(:server_generated)
        CSSHighlighting = new(:css_highlighting)
        None = new(:none)
      end
    end

    class RichDiffStrategy < T::Enum
      enums do
        Default = new(:default) # Default loading strategy, loads rich diff data if displays by default
        Full = new(:full) # Load full rich diff data - used for async loading of deferred rich diffs
        Skip = new(:skip) # Skip loading rich diff data
      end
    end

    class DiffLine < T::Struct
      const :ast, T.nilable(SyntaxHighlightedDiff::StylingDirectives)
      const :display_no_new_line_warning, T::Boolean
      # can be plain text, plain HTML with intra-line changes, or syntax highlighted HTML
      const :html, String
      const :left, T.nilable(Integer)
      const :line_number, Integer
      const :position, Integer
      const :right, T.nilable(Integer)
      const :text, String
      const :type, String
      const :has_added_ambiguous_characters, T::Boolean
    end

    class DiffEntry < T::Struct
      const :additions, Integer
      const :binary_size, T.nilable(Integer)
      const :changes, Integer
      const :deletions, Integer
      const :diff_index, Integer
      const :is_binary, T::Boolean
      const :is_submodule, T::Boolean
      const :is_too_big, T::Boolean
      const :lines, T::Array[DiffLine]
      const :new_tree_entry, T.nilable(TreeEntry)
      const :old_tree_entry, T.nilable(TreeEntry)
      const :path, String
      const :reviewed, T::Boolean
      const :status_label, String
      const :truncated_reason, T.nilable(String)
      const :rich_diff, T.nilable(PullRequests::PageData::Diffs::RichDiff::Loader::Data)
      const :submodule, T.nilable(Diffs::PageData::Submodule::Loader::Data)
    end

    class Data < T::Struct
      const :before_commit_oid, String
      const :after_commit_oid, String
      const :diff_entries, T::Array[DiffEntry]
    end

    sig do
      params(
        diff: GitHub::Diff,
        ignore_whitespace: T::Boolean,
        timeout: T.any(Integer, Float),
        top_only: T::Boolean,
        viewed_files: PullRequestUserReviews,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        pull_request: PullRequest,
        paths: T::Array[String],
        highlighting_strategy: T.nilable(HighlightStrategy),
        rich_diff_strategy: T.nilable(RichDiffStrategy),
        show_hidden: T.nilable(T::Boolean),
        repository: T.nilable(Repository),
        context_lines: T.nilable(T::Hash[String, T::Array[T::Range[Integer]]]),
        current_user: T.nilable(User),
        short_path: T.nilable(String),
      ).returns(Data)
    end
    def self.load(
      diff:,
      ignore_whitespace:,
      timeout:,
      top_only:,
      viewed_files:,
      limit_config:,
      pull_request:,
      paths: [],
      highlighting_strategy: HighlightStrategy::ServerGenerated,
      rich_diff_strategy: RichDiffStrategy::Default,
      show_hidden: false,
      repository: nil,
      context_lines: nil,
      current_user: nil,
      short_path: nil
    )
      new(
        diff: diff,
        ignore_whitespace: ignore_whitespace,
        timeout: timeout,
        top_only: top_only,
        paths: paths,
        highlighting_strategy: highlighting_strategy,
        rich_diff_strategy: rich_diff_strategy,
        pull_request: pull_request,
        repository: repository,
        show_hidden: show_hidden,
        context_lines: context_lines,
        current_user: current_user,
        viewed_files: viewed_files,
        limit_config: limit_config,
        short_path: short_path
      ).load
    end

    sig do
      params(
        diff: GitHub::Diff,
        ignore_whitespace: T::Boolean,
        timeout: T.any(Integer, Float),
        top_only: T::Boolean,
        viewed_files: PullRequestUserReviews,
        repository: T.nilable(Repository),
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        pull_request: PullRequest,
        highlighting_strategy: T.nilable(HighlightStrategy),
        rich_diff_strategy: T.nilable(RichDiffStrategy),
        show_hidden: T.nilable(T::Boolean),
        context_lines: ContextLines,
        current_user: T.nilable(User),
        paths: T::Array[String],
        short_path: T.nilable(String),
      ).void
    end
    def initialize(diff:, ignore_whitespace:, timeout:, top_only:, viewed_files:, repository:, limit_config:, pull_request:, highlighting_strategy: HighlightStrategy::ServerGenerated, rich_diff_strategy: RichDiffStrategy::Default, show_hidden: false, context_lines: nil, current_user: nil, paths: [], short_path: nil)
      @diff = diff
      @ignore_whitespace = ignore_whitespace
      @paths = paths
      @repository = repository
      @limit_config = limit_config
      @pull_request = pull_request
      @highlighting_strategy = highlighting_strategy
      @rich_diff_strategy = rich_diff_strategy
      @timeout = timeout
      @top_only = top_only
      @show_hidden = show_hidden
      @context_lines = context_lines
      @current_user = current_user
      @viewed_files = viewed_files
      @short_path = short_path
    end

    sig { returns(Data) }
    def load
      with_telemetry do
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
        @diff.context_lines = instrument_context_lines(filtered_context_lines)
        @diff.read_full_blob_for_context_lines = FeatureFlag.vexi.enabled?(:prx_rich_diff_expand, @current_user, default: false)
        @limit_config.apply_files_page_limit(@diff)
        # We need to set diff entry size limits before loading the diff entries.
        set_single_entry_limits(@diff, @paths, @top_only)

        @diff.load_diff

        diff_entries = T.let([], T::Array[GitHub::Diff::Entry])
        content_tree_entries = T.let([], T::Array[TreeEntry])
        diff_entries_with_content_lookup = T.let({}, T::Hash[String, GitHub::Diff::Entry])

        @diff.entries.each do |diff_entry|
          next if diff_entry.truncated?

          diff_entries << diff_entry

          tree_entry = diff_entry_blob(diff_entry, @repository)

          # Determine which entries have content so we can prefill
          if has_content?(diff_entry, tree_entry, @show_hidden)
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
        highlighted_diff.highlight!(diff_entries) if @highlighting_strategy == HighlightStrategy::ServerGenerated
        highlighted_diff.highlight_with_styled_directives!(diff_entries) if @highlighting_strategy == HighlightStrategy::CSSHighlighting

        # Calculate skip_dependency_review once for all entries
        skip_dependency_review = with_database_error_fallback(fallback: true) do
          if @current_user.present?
            # exceeds_manifest_limit? internally checks if the repository has dependency graph + review enabled
            DependencyReview::ManifestLimitHelper.exceeds_manifest_limit?(diffs: @diff, repository: @repository)
          else
            true # If we don't have a current user, we skip dependency review
          end
        end

        diff_entries = diff_entries.map.with_index do |diff_entry, i|
          lines = if diff_entries_with_content_lookup.key?(diff_entry.path_digest)
            if @highlighting_strategy == HighlightStrategy::CSSHighlighting
              styling_directives = highlighted_diff.styling_directive(diff_entry)
            elsif @highlighting_strategy == HighlightStrategy::ServerGenerated
              syntax_highlighted_lines = highlighted_diff.colorized_lines(diff_entry)&.freeze
              syntax_highlighted_lines&.each(&:freeze)
            end

            diff_lines(diff_entry, syntax_highlighted_lines, styling_directives)
          else
            []
          end

          # Reuse the same TreeEntry objects so we don't lose prefilled attributes
          new_tree_entry = content_tree_entries.find { |entry| entry.path == diff_entry.b_path } unless diff_entry.deleted?
          old_tree_entry = content_tree_entries.find { |entry| entry.path == diff_entry.a_path } if diff_entry.deleted?
          new_tree_entry ||= new_tree_entry(diff_entry, @repository)
          old_tree_entry ||= old_tree_entry(diff_entry, @repository)

          # preload tree entry data
          new_tree_entry&.line_count
          old_tree_entry&.line_count
          new_tree_entry&.generated?

          unless @rich_diff_strategy == PullRequests::PageData::Diffs::Contents::Loader::RichDiffStrategy::Skip
            rich_diff_data = with_database_error_fallback(fallback: nil) do
              PullRequests::PageData::Diffs::RichDiff::Loader.load(
                diff_entry: diff_entry,
                old_tree_entry: old_tree_entry,
                new_tree_entry: new_tree_entry,
                binary_sizes: binary_sizes,
                skip_dependency_review: skip_dependency_review || false,
                repository: T.must(@repository),
                current_user: @current_user,
                short_path: @short_path,
                force_load_rich_diff: @rich_diff_strategy == PullRequests::PageData::Diffs::Contents::Loader::RichDiffStrategy::Full
              )
            end
          end

          if diff_entry.submodule?
            submodule_data = with_database_error_fallback(fallback: nil) do
              Diffs::PageData::Submodule::Loader.load(
                diff_entry: diff_entry,
                repository: T.must(@repository),
                current_user: @current_user
              )
            end
          end

          DiffEntry.new(
            additions: diff_entry.additions || 0,
            binary_size: binary_size(binary_sizes, diff_entry),
            changes: diff_entry.changes || 0,
            deletions: diff_entry.deletions || 0,
            diff_index: i,
            is_binary: diff_entry.binary?,
            is_submodule: diff_entry.submodule?,
            is_too_big: diff_entry.too_big?,
            lines: lines,
            new_tree_entry: new_tree_entry,
            old_tree_entry: old_tree_entry,
            path: diff_entry.path,
            reviewed: @viewed_files.reviewed?(diff_entry.path),
            status_label: diff_entry.status_label || "",
            truncated_reason: diff_entry.truncated_reason,
            rich_diff: rich_diff_data,
            submodule: submodule_data,
          )
        end

        Data.new(
          before_commit_oid: @diff.sha1,
          after_commit_oid: @diff.sha2,
          diff_entries: diff_entries,
        )
      end
    end

    sig do
      params(
        user_agent: T.nilable(String),
        current_user: T.nilable(User),
        params: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters)
      ).returns(PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy)
    end
    def self.syntax_highlighting_method(user_agent, current_user, params)
      browser = T.let(Browser.new(user_agent || ""), Browser::Base)

      # Unsupported browsers that we support as of June 2025:
      # - Firefox <140 and Safari <17.2
      # These will fallback to the server-side highlighting strategy.
      if browser.firefox?(["<140"]) || browser.safari?(["<17.2"])
        return PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy::ServerGenerated
      end

      if FeatureFlag.vexi.enabled?(:prx_files_css_highlighting, current_user, default: false) || params.has_key?(:css_highlighting)
        PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy::CSSHighlighting
      else
        PullRequests::PageData::Diffs::Contents::Loader::HighlightStrategy::ServerGenerated
      end
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
        headers = repository.read_object_headers(oids)

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

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        syntax_highlighted_diff: T.nilable(T::Array[String]),
        styling_directives: T.nilable(T::Array[SyntaxHighlightedDiff::StylingDirectives])
      ).returns(T::Array[DiffLine])
    end
    def diff_lines(diff_entry, syntax_highlighted_diff, styling_directives)
      show_no_newline_warning = valid_no_new_line_file?(diff_entry.path)

      diff_entry.enumerator.map do |line|
        line = T.let(line, GitHub::Diff::Line)

        line_has_ambiguous_characters = if FeatureFlag.vexi.enabled?(:detect_homoglyphs, @current_user, default: false)
          has_added_ambiguous_characters?(line: line, pull_request: @pull_request, repository: @repository)
        else
          false
        end

        if syntax_highlighted_diff
          html = syntax_highlighted_diff[line.position]
          related_html = line.related_line ? syntax_highlighted_diff[line.related_line.position] : nil
          html = mark_intra_line_changes_html(line, html, related_html)
        else
          html = \
            if line.related_line
              mark_intra_line_changes(line)
            else
              sanitize_html_for_unhighlighted_diff_line_with_no_related_lines(line)
            end
        end

        if styling_directives
          styling_directive = styling_directives[line.position]
        end

        html = ERB::Util.h(html)
        html.chomp!
        html.gsub!("\r", "")
        html = "<br>" unless html.present?

        DiffLine.new(
          type: line.type.to_s.upcase,
          line_number: line.current,
          text: line.text,
          ast: styling_directive.is_a?(Array) ? styling_directive : nil,
          display_no_new_line_warning: show_no_newline_warning && line.nonewline?,
          position: line.position,
          html: html,
          left: line.left == -1 ? nil : line.left,
          right: line.right == -1 ? nil : line.right,
          has_added_ambiguous_characters: line_has_ambiguous_characters,
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

    sig { params(diff_entry: GitHub::Diff::Entry, tree_entry: T.nilable(TreeEntry), show_hidden: T.nilable(T::Boolean)).returns(T::Boolean) }
    def has_content?(diff_entry, tree_entry, show_hidden = false)
      return false if tree_entry.nil?

      diff_is_hidden = !show_hidden && (diff_entry.too_big? || diff_entry.deleted? || tree_entry.generated?)

      !diff_is_hidden && !diff_entry.text.blank?
    end

    # For INJECTED_CONTEXT line html, the client expects the leading ~ character to be replaced with a single whitespace
    # character (the same leading character used for CONTEXT lines). For syntax highlighted lines and unhighlighted lines
    # with related lines, this is handled as part of building the HTML. For unhighlightable lines without related lines,
    # this method implements the same logic.
    #
    # Making changes? Update duped method Commit::ReactDiffLinesHelper#sanitize_html_for_unhighlighted_diff_line_with_no_related_lines
    sig { params(line: GitHub::Diff::Line).returns(String) }
    def sanitize_html_for_unhighlighted_diff_line_with_no_related_lines(line)
      return line.text unless line.injected_context?
      return line.text unless line.text.start_with?("~")
      # Replace leading tilde with a single whitespace character for consistent handling on the client side
      " #{line.text[1..-1]}"
    end

    sig { params(context_lines: ContextLines).returns(ContextLines) }
    def instrument_context_lines(context_lines)
      if context_lines
        total = context_lines.values.sum(&:size)
        GitHub.dogstats.distribution("pull_requests.diff_contents.injected_ranges.count_dist", total)
      end

      context_lines
    end

    sig { returns(ContextLines) }
    def filtered_context_lines
      context_lines = @context_lines

      if context_lines.present? && @paths.any?
        context_lines.slice(*T.unsafe(@paths))
      else
        context_lines
      end
    end
  end
end
