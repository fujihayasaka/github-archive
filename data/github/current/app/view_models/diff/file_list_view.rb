# typed: true
# frozen_string_literal: true

module Diff
  class FileListView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    extend T::Sig

    MAX_NOTEBOOK_DIFFS = 3

    include ActionView::Helpers::NumberHelper
    include DiffHelper
    include EnterpriseManagedUsersHelper
    include GitHub::Memoizer
    include GitHub::ResilienceMixin

    attr_reader :diffs, :params, :prose_url_hints, :highlight, :progressive
    attr_reader :commit, :pull, :pull_comparison, :number_offset
    attr_reader :display_diff_ajax_enabled
    attr_reader :cap_view_filter
    attr_reader :user_reviewed_files
    attr_reader :notebook_diffs

    alias_method :highlight?, :highlight
    alias_method :progressive?, :progressive

    def self.file_view_class
      @file_view_class
    end

    def self.file_view_class=(klass)
      @file_view_class = klass
    end

    self.file_view_class = Diff::FileView

    def after_initialize
      @notebook_diffs = 0

      unless defined?(@expandable)
        @expandable = true
      end

      unless defined?(@commentable)
        @commentable = true
      end

      unless defined?(@highlight)
        @highlight = true
      end

      unless defined?(@progressive)
        @progressive = false
      end

      unless defined?(@prose_url_hints)
        @prose_url_hints = {}
      end

      unless defined?(@number_offset)
        @number_offset = 0
      end
    end

    def increment_notebook_diffs!(file_view)
      return unless file_view.is_notebook?
      @notebook_diffs += 1
    end

    def max_notebook_diffs?
      @notebook_diffs > MAX_NOTEBOOK_DIFFS
    end

    # uses a batch RPC call to retrieve the file sizes of each blob,
    # creating a hash containing the filesize of each blob in this file list
    def prepare_blob_sizes(entries)
      @blob_sizes = {}
      oids = []

      entries.each do |diff|
        oids << diff.a_blob << diff.b_blob if diff.binary?
      end

      oids.compact!
      oids.uniq!

      if oids.any?
        headers = repository.rpc.read_object_headers(oids)

        headers.each_with_index do |obj_header, i|
          oid = oids[i]
          @blob_sizes[oid] = obj_header["size"]
        end
      end
    end

    def repository
      @repository || (diffs.respond_to?(:repo) && diffs.repo)
    end

    def blob_sizes
      @blob_sizes || {}
    end

    attr_reader :expandable
    alias_method :expandable?, :expandable

    attr_reader :in_wiki_context

    # Yields a `Diff::FileView` to the `block` given for every
    # diff in the list managed by the viewmodel in `diffs` that
    # contains actual changes.
    def each_diff(&block)
      entries = diffs.to_a
      entries.reject!(&:truncated?) if progressive?

      prepare_blob_sizes(entries)

      render_diffs = 0
      file_views = entries.each_with_index.map do |diff, index|
        number = number_offset + index
        blob_a_size, blob_b_size = blob_sizes[diff.a_blob], blob_sizes[diff.b_blob]

        file_view = self.class.file_view_class.new(
          diff: diff,
          diff_number: number,
          repository: repository,
          current_user: current_user,
          blob_a_size: blob_a_size,
          blob_b_size: blob_b_size,
          user_reviewed_files: user_reviewed_files,
          base_sha: diffs.base_sha
        )

        if file_view.render_diff?
          render_diffs += 1
          file_view.hidden_render_diff = true if render_diffs > GitHub.max_render_diffs_per_page
        end

        file_view
      end

      file_views.each(&block)
    end

    # Determines whether "Display source diff" and "Display rich diff" button
    # render as non-ajax links or ajax-backed forms.
    #
    # In most cases, if view is progressive, then these buttons should have ajax
    # enabled. However there are special cases (like blob#delete) where we need
    # to render the non-ajax links instead.
    #
    # See https://github.com/github/github/pull/145138 for more context.
    def display_diff_ajax_enabled?
      return @display_diff_ajax_enabled if defined? @display_diff_ajax_enabled
      @display_diff_ajax_enabled = progressive?
    end

    # Returns true if the diff was too big, had too many files or was truncated
    # due to timeout while generating the diff.
    def truncated?
      if progressive?
        total_file_views > diffs.max_files
      else
        diffs.truncated?
      end
    end

    # Is the total number of changed files in this diff larger than max limit?
    #
    # NOTE: The maximum file count used here is defined by GitRPC::Diff::Summary#max_files,
    # which should not be confused with GitHub::Diff#max_files:
    #
    #   - GitHub::Diff#max_files defaults to 300
    #   - GitRPC::Diff::Summary#max_files defaults to 3000
    #
    # Returns Boolean
    def too_many_files?
      diffs.summary.too_many_files?
    end

    def too_many_files_changed_message
      "The diff you're trying to view is too large. We only load the first #{diffs.summary.max_files} changed files."
    end

    # Returns true if the diff had too many files
    delegate :truncated_for_max_files?, to: :diffs

    # Returns true if we only have partial diff output due to timeout
    delegate :truncated_for_timeout?, to: :diffs

    # Returns a message suitable for displaying in a warning banner at the
    # top of the page, or nil if the diff was not truncated.
    def truncate_message_for_the_toc
      msg = diffs.truncated_reason
      case msg
      when "maximum diff size exceeded.", "maximum number of lines exceeded."
        "Sorry, we could not display the entire diff because it was too big."
      when "maximum file count exceeded."
        "Sorry, we could not display the entire diff because too many files changed."
      when /^maximum file count exceeded: total=(\d+)/
        "Sorry, we could not display the entire diff because too many files (#{diffs.changed_files}) changed."
      when "timeout reached."
        "Sorry, we could not display the entire diff because it took too long to generate."
      else
        msg
      end
    end

    def restricted_each_diff(&block)
      each_diff.reject do |diff_view|
        diff_view.diff.truncated_reason
      end.each(&block)
    end

    sig { returns(T::Array[Diff::SummaryDeltaView]) }
    def summary_delta_views
      diffs.summary.deltas.map { |d| Diff::SummaryDeltaView.new(d) }
    end

    delegate :available?, :empty?, :timed_out?, :too_busy?,
             :corrupt?, :changed_files, :ignore_whitespace?,
             to: :diffs

    def total_additions
      diffs.additions
    end

    def total_deletions
      diffs.deletions
    end

    def total_file_views
      diffs.deltas.size
    end

    def commentable?
      return false if repository.try(:locked_on_migration?)
      return false if repository.try(:archived?)
      return false if cap_view_filter && emu_contribution_blocked?(repository)
      @commentable && commenting_feature_enabled?
    end
    attr_reader :commentable

    def load_more?
      return false unless progressive?

      remaining_entries_count = total_file_views - loaded_diff_entries_count
      remaining_entries_count > 0
    end

    def tree_name
      if pull && pull.open?
        pull.head_ref_name
      elsif pull
        pull.head_sha
      else
        repository.default_branch
      end
    end

    def load_unchanged_files_with_annotations?
      return false unless pull
      return false if GitHub.flipper[:hide_unchanged_files].enabled?(current_user)

      should_load = annotations.non_diff_paths.present?

      GitHub.dogstats.increment(
        "checks.load_unchanged_files_with_annotations",
        tags: ["should_load:#{should_load}"],
      )

      should_load
    end

    # Internal: Count of diff entries loaded
    def loaded_diff_entries_count
      diffs.entries.count { |diff_entry| !diff_entry.truncated? }
    end

    def next_start_entry_index
      loaded_diff_entries_count
    end

    # Build the comment threads for each path in the file listing.
    #
    # Returns a ReviewThreads collection.
    def threads
      return ReviewThreads.new([]) unless commenting_feature_enabled?

      @threads ||= if commit
        CommitCommentThread.review_threads(viewer: current_user, commit: commit, repository: repository)
      elsif pull_comparison
        pull_comparison.review_threads_for(viewer: current_user)
      else
        ReviewThreads.new([])
      end
    end

    # Returns a collection of CommitComments or PullRequestReviewComments
    def comments_for(path)
      threads.path(path).flat_map(&:comments)
    end

    # Collect the file-level comment threads for each path in the file listing.
    #
    # Returns a ReviewThreads collection.
    def file_level_threads
      return ReviewThreads.new([]) unless commenting_feature_enabled?
      return ReviewThreads.new([]) if commit

      @file_level_threads ||= if pull_comparison
        pull_comparison.file_review_threads_for(viewer: current_user)
      else
        ReviewThreads.new([])
      end
    end

    def file_level_threads_for(path)
      file_level_threads.path(path)
    end

    memoize def annotations
      return DiffAnnotations.new([]) unless repository.respond_to?(:annotations_for)

      annotations = with_database_error_fallback(fallback: []) do
        repository.annotations_for(sha: diffs.sha2, limit: CheckAnnotation::MAX_READ_LIMIT)
      end

      diff_annotations = DiffAnnotations.new(annotations, diffs)
      diff_annotations.load_code_scanning_alerts(viewer: current_user, repository: repository)
      diff_annotations
    end

    def has_comments?(diff_entry)
      !comments_for(diff_entry.a_path).empty? || !comments_for(diff_entry.b_path).empty?
    end

    def attributes_commit_oid
      if pull
        pull.head_sha
      else
        diffs.parsed_sha2
      end
    end

    def valid_file_types
      diffs.file_types
    end

    def defer_notebook_diff_loading?(view)
      max_notebook_diffs? && progressive? && view.is_notebook?
    end

    private

    def commenting_feature_enabled?
      # allow us to turn of commit comments for problematic repositories
      return false if commit && GitHub.flipper[:disable_commit_comments].enabled?(repository)

      return true unless ignore_whitespace? # always return comments for regular diffs
      !commit                               # no whitespace comments on commit diffs yet :(
    end
  end
end
