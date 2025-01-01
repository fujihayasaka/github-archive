# typed: true
# frozen_string_literal: true

class PullRequestReviewThread < ApplicationRecord::Domain::IssuesPullRequests
  class PositionlessReviewThreadCreated < StandardError; end
  class ResolveReviewThreadError < StandardError; end
  class PositionSyncError < StandardError; end

  # Internal: The maximum number of lines to return for a multi-line comment excerpt.
  MAX_MULTI_LINE_EXCERPT_LINES = 100
  OUTSIDE_DIFF_CONTEXT_MARGIN = 2
  SUBJECT_TYPES = %i[line file].freeze

  include GitHub::Relay::GlobalIdentification
  extend GitHub::Encoding
  include GitHub::UTF8
  include GitHub::Validations
  include LegacyImportable
  include Instrumentation::Model

  # Used to validate the end position value and set various position attributes.
  attr_accessor :end_position_data

  # Used to validate the start position value and set the :start_position_offset attribute.
  attr_accessor :start_position_data

  # The (possibly augmented by injection) diff stored in memory while this
  # thread is being initially created.
  attr_accessor :creation_diff

  # Used to bypass active record callbacks on create via the
  # CreateNewPullRequestReviewCommentOrchestration
  attr_accessor :skip_create_callbacks
  alias_method :skip_create_callbacks?, :skip_create_callbacks

  attr_writer :current_comparison


  sig { returns(T.nilable(PullRequests::CommentPosition::Positions)) }
  attr_accessor :preloaded_positioning

  GLOBAL_ID_V2_IDENTIFIER = "v2".freeze

  force_utf8_encoding :path

  attribute :compressed_diff_hunk, CompressedBinary.new(name, :compressed_diff_hunk)

  belongs_to :pull_request
  belongs_to :pull_request_review
  belongs_to :resolver, class_name: "User"
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  has_many :review_comments,
    class_name: "PullRequestReviewComment",
    inverse_of: :pull_request_review_thread

  before_validation :set_repository_id, unless: :skip_create_callbacks?
  before_validation :initialize_end_position_data, on: :create, unless: :skip_create_callbacks?
  before_validation :write_end_position_attributes, on: :create, unless: :skip_create_callbacks?
  before_validation :initialize_original_attribute_values, on: :create, unless: :skip_create_callbacks?
  before_validation :write_start_position_offset, on: :create, if: :on_line?, unless: :skip_create_callbacks?
  before_create :truncate_diff_hunk, if: :on_line?, unless: :skip_create_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validate :validate_end_position_data, on: :create, unless: -> { T.bind(self, PullRequestReviewThread); (importing_historical_thread? || skip_create_callbacks?) }
  validate :validate_start_position_offset, on: :create, if: -> { T.bind(self, PullRequestReviewThread); (on_line? && !skip_create_callbacks?) }
  validates :compressed_diff_hunk, unicode: true, if: -> { T.bind(self, PullRequestReviewThread); (on_line? && !skip_create_callbacks?) }
  validates :diff_hunk, presence: true, if: -> { T.bind(self, PullRequestReviewThread); (on_line? && !skip_create_callbacks?) }
  validates :original_position, presence: true, on: :create, if: -> { T.bind(self, PullRequestReviewThread); (should_validate_original_position? && !skip_create_callbacks?) }
  validates :repository_id, presence: true, on: :create, unless: :skip_create_callbacks?

  after_create :ensure_synced_with_pull, if: -> { T.bind(self, PullRequestReviewThread); (should_ensure_synced_with_pull_request? && !skip_create_callbacks?) }  # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :ensure_file_part_of_diff, if: -> { T.bind(self, PullRequestReviewThread); (on_file? && !skip_create_callbacks?) } # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  after_commit :instrument_creation, on: :create, unless: :skip_create_callbacks? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_deletion, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  enum :subject_type, SUBJECT_TYPES, prefix: :on

  # Public: Scope to filter legacy review threads
  #
  # Legacy review threads are threads that do _not_ belong to a `PullRequestReview`
  scope :legacy, -> {
    where(pull_request_review_id: nil)
  }

  # Public: Scope to filter threads visible to the viewer
  #
  # viewer - User viewing the threads (nil means anonymous)
  #
  # Notice: This logic needs to be kept in sync with `#async_visible_to?`.
  scope :visible_to, -> (viewer) {
    comments_scope = PullRequestReviewComment.
      visible_to(viewer).
      where(<<~SQL)
        `pull_request_review_threads`.`id` = `pull_request_review_comments`.`pull_request_review_thread_id`
        AND `pull_request_review_threads`.`pull_request_id` = `pull_request_review_comments`.`pull_request_id`
      SQL

    where("EXISTS (#{comments_scope.to_sql})", comments_scope.where_values_hash)
  }

  # Public: Scope to grab all threads that are not in a pending state for a given pull request
  scope :non_pending_review_threads, -> (pull_request_id) {
    PullRequestReviewThread.where(pull_request_id: pull_request_id)
      .joins(:pull_request_review)
      .where.not(
        pull_request_review: {
          state: PullRequestReview.state_value(:pending)
        })
  }

  def compressed_diff_hunk
    utf8(read_attribute(:compressed_diff_hunk))
  end

  # We can't just alias_method these because the attribute generated methods don't exist yet.
  def diff_hunk
    compressed_diff_hunk
  end

  def diff_hunk=(value)
    self.compressed_diff_hunk = value
  end

  def build_reply(pull_request_review: nil, user: pull_request_review.user, body:)
    first_comment = review_comments.first!
    first_comment.build_reply(review: pull_request_review, body: body, user: user)
  end

  # Public: Instantiates a new PullRequestReviewComment attached to this thread.
  #
  # user - the User who commented. Defaults to the writer of the review
  # body - the String body of the comment
  # path - the path of the right side of the diff entry on which the comment has been left
  # diff - the GitHub::Diff on which this comment has been left. Defaults to the latest diff for the pull request.
  # start line & side - The start line of a multi line comment and the side of the diff it is on.
  # line & side - The line and side of the comment. The end of the range for a multi-line comment.
  #
  # Returns a new PullRequestReviewComment which is part of this thread's review_comments collection
  # TODO: Thread attribute assignment shouldn't happen here, or we should rename or something
  def build_first_comment(user: T.must(pull_request_review).user, body:, path:, diff: nil,
    start_line: nil, start_side: :right, line: nil, side: :right)

    self.path ||= path

    diff ||= T.must(pull_request).historical_comparison.diffs
    diff = diff.only_params

    if on_file?
      self.left_blob = side.to_sym == :left
      self.end_position_data = PullRequestReviewComment::FileLevelPositionData.async_from_thread(self, diff: diff).sync
    else
      self.start_position_data = diff_position_data(diff, path, start_side, start_line)
      self.end_position_data = diff_position_data(diff, path, side, line)
    end

    review_comments.build(
      pull_request: pull_request,
      pull_request_review: pull_request_review,
      user: user,
      body: body
    )
  end

  # Public: Instantiates a new PullRequestReviewComment attached to this thread. This is
  #   primarily a legacy method supporting the API endpoints which support specifying a comment's
  #   position by its offset into the diff text.
  #
  # user - the User who commented
  # body - the String body of the comment
  # pull_comparison - the PullRequest::Comparison on which this comment has been left
  # position - the integer offset into the diff text on which this comment is being left
  # path - the path of the right side of the diff entry on which the comment has been left
  #
  # Returns a new PullRequestReviewComment which is part of this thread's review_comments collection
  def build_first_diff_position_comment(user:, body:, diff: nil, position:, path:, position_is_used: nil)
    diff ||= T.must(pull_request).async_diff.sync
    self.end_position_data = legacy_position_data(diff, path, position)
    review_comments.build(
      pull_request: pull_request,
      pull_request_review: pull_request_review,
      position_is_used: position_is_used,
      user: user,
      body: body,
    )
  end

  def self.id_for(thread_id: nil, first_comment_id: nil, version: 2)
    case version
    when 1
      raise ArgumentError, "first_comment_id cannot be nil for version 1" unless first_comment_id
      first_comment_id.to_s
    when 2
      raise ArgumentError, "thread_id cannot be nil for version 2" unless thread_id
      [thread_id, GLOBAL_ID_V2_IDENTIFIER].join(":")
    end
  end

  def global_id
    self.class.id_for(thread_id: id, version: 2)
  end

  # Public: Visiblity check for thread
  #
  # viewer - User viewing the threads (nil means anonymous)
  #
  # Notice: This logic needs to be kept in sync with the scope `visible_to`.
  def async_visible_to?(viewer)
    async_review_comments_for(viewer).then do |review_comments|
      review_comments.any? { |comment| comment.visible_to?(viewer) }
    end
  end

  def published?
    if review = pull_request_review
      !review.pending?
    else
      false
    end
  end

  def legacy?
    pull_request_review_id.nil?
  end

  def has_positioning_data?
    # Path always has to be present in all cases where a thread has positioning
    # data so we can simply check for that instead of a more complicated check.
    # If it does not have this then it has not been backfilled yet and lacks
    # positioning data.
    path.present?
  end

  def code_scanning?
    if review = pull_request_review
      review.code_scanning?
    else
      false
    end
  end

  def conversation?
    return true unless code_scanning?
    comments.size > 1
  end

  def async_resolver_for(viewer)
    @async_resolver_for[viewer] if defined?(@async_resolver_for)

    @async_resolver_for = Hash.new do |hash, key|
      hash[key] = async_resolver.then do |resolver|
        next if resolver&.hide_from_user?(key)

        resolver
      end
    end
    @async_resolver_for[viewer]
  end

  def async_review_comments_for(viewer)
    return @async_review_comments_for_viewer[viewer] if defined?(@async_review_comments_for_viewer[viewer])

    @async_review_comments_for_viewer = Hash.new do |hash, key|
      hash[key] = Platform::Loaders::PullRequestReviewCommentsForReviewThread.load(id, viewer).then do |comments|
        comments.sort_by(&:id)
      end
    end
    @async_review_comments_for_viewer[viewer]
  end

  def self.sliced_comments(comments, pagination_options)
    if pagination_options[:after]
      comments = comments.drop_while do |comment|
        comment.id != pagination_options[:after]
      end.drop(1)
    end

    if pagination_options[:before]
      comments = comments.take_while do |comment|
        comment.id != pagination_options[:before]
      end
    end

    comments
  end

  batch_method(:prelude_paginated_review_comments_for) do |review_threads, viewer, pagination_options|
    results = Promise.all(review_threads.map do |review_thread|
      review_thread.async_review_comments_for(viewer).then do |comments|
        comments = sliced_comments(comments, pagination_options)
        first_group = comments.take(pagination_options[:first])
        remaining_comments = comments.drop(pagination_options[:first])

        hidden_items = []
        last_group = []
        if remaining_comments.length > 0
          last_group = remaining_comments.last(pagination_options[:last]) if pagination_options[:last]
          hidden_items = remaining_comments - last_group
        end

        { first_group: first_group, last_group: last_group, hidden_items_count: hidden_items.count, hidden_comment_ids: hidden_items.map(&:id) }
      end
    end).sync

    review_threads.zip(results).to_h
  end

  batch_method(:prelude_all_review_comments) do |review_threads, viewer|
    results = Promise.all(review_threads.map do |review_thread|
      review_thread.async_review_comments_for(viewer)
    end).sync

    review_threads.zip(results).to_h
  end

  batch_method(:prelude_viewer_can_resolve) do |review_threads, viewer|
    results = Promise.all(review_threads.map do |review_thread|
      review_thread.async_can_resolve(viewer)
    end).sync

    review_threads.zip(results).to_h
  end

  batch_method(:prelude_viewer_can_unresolve) do |review_threads, viewer|
    results = Promise.all(review_threads.map do |review_thread|
      review_thread.async_can_unresolve(viewer)
    end).sync

    review_threads.zip(results).to_h
  end

  def async_to_deprecated_thread
    Promise.all([
      async_pull_request,
      async_review_comments,
    ]).then do |pull_request, comments|
      next if comments.nil? || comments.empty?

      comments = comments.sort_by do |comment|
        [comment.pull_request_review_thread_id, comment.created_at, comment.id]
      end

      GitHub::PrefillAssociations.prefill_associations(comments, :pull_request, available_records: [pull_request])

      async_original_pull_request_comparison.then do |pull_comparison|
        ::DeprecatedPullRequestReviewThread.new(
          pull: pull_request,
          pull_comparison: pull_comparison,
          path: path,
          position: original_position,
          comments: comments,
        )
      end
    end
  end

  def platform_type_name
    "PullRequestReviewThread"
  end

  def resolve(resolver:)
    # Not all threads count as conversations. Non conversation threads cannot be resolved.
    raise ResolveReviewThreadError, "The thread is not a conversation and cannot be resolved" unless conversation?

    self.resolver = resolver
    self.resolved_at = Time.current
    self.save!

    if pull_request_base_requires_review_thread_resolution?
      channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
      GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)

      T.must(pull_request).enqueue_auto_merge_job_if_enabled
    end

    instrument :resolve, resolver_id: resolver.id, resolver: resolver.display_login
    GitHub.instrument("pull_request_review_thread.resolved",
      thread_id: id,
      pull_request_id: pull_request_id,
      actor_id: resolver.id,
      action: "resolved"
    )
    GlobalInstrumenter.instrument("pull_request_review_thread.resolved",
      pull_request_review_thread: self,
      actor: resolver,
    )
  end

  def unresolve(unresolver:)
    self.resolver = nil
    self.resolved_at = nil
    self.save!

    if pull_request_base_requires_review_thread_resolution?
      channel = GitHub::WebSocket::Channels.pull_request_state(pull_request)
      GitHub::WebSocket.notify_pull_request_channel(pull_request, channel)
    end

    instrument(:unresolve, unresolver_id: unresolver.id, unresolver: unresolver.display_login)
    GitHub.instrument("pull_request_review_thread.unresolved",
      thread_id: id,
      pull_request_id: pull_request_id,
      actor_id: unresolver.id,
      action: "unresolved"
    )

    GlobalInstrumenter.instrument("pull_request_review_thread.unresolved",
      pull_request_review_thread: self,
      actor: unresolver,
    )
  end

  def pull_request_base_requires_review_thread_resolution?
    T.must(pull_request).requires_review_thread_resolution?
  end

  # Determine whether the given viewer can see this thread.
  #
  # viewer - A User or nil for a anonymous viewer.
  #
  # Returns a Promise<Boolean>.
  def async_hide_from_user?(viewer)
    async_review_comments.then do |review_comments|
      review_comments.none? { |comment| comment.visible_to?(viewer) }
    end
  end

  # Public: the side of the diff to which the first of commented lines applies.
  #
  # Returns `:left` for deletions, `:right` for additions and context, and `nil`
  # for single-line comments.
  def start_side
    return nil unless start_position_offset
    diff_line = original_start_diff_line
    return nil unless diff_line # diff was likely truncated
    diff_line.type == :deletion ? :left : :right
  end

  # Public: Returns the diff side of the comment's starting line.
  #
  # Returns a Promise resolving to a Symbol :right or :left, or nil.
  def async_start_side(diff = nil)
    return Promise.resolve(nil) unless start_position_offset

    async_start_line(diff).then do |start_line|
      next nil unless start_line

      start_line.deletion? ? :left : :right
    end
  end

  # Public: The adjusted 1-indexed blob position of the first of the
  # commented-on lines of a mutli-line comment.
  #
  # Returns an integer, or `nil` for single-line or outdated comments.
  def start_line_number
    async_start_line_number.sync
  end

  def async_start_line_number
    return Promise.resolve(nil) unless start_position_offset
    async_start_line.then do |line|
      line.current if line
    end
  end

  # Internal: Finds the comment's start line in the diff.
  #
  # Returns a Promise resolving to a GitHub::Diff::Line or nil.
  def async_start_line(diff = nil)
    async_adjusted_selected_lines(diff).then do |lines|
      lines.first
    end
  end

  # Internal: Finds the comment's end line in the diff.
  #
  # Returns a Promise resolving to a GitHub::Diff::Line or nil.
  def async_end_line(diff = nil)
    async_adjusted_selected_lines(diff).then do |lines|
      lines.last
    end
  end

  # Public: The adjusted 1-indexed blob position of a single-line comment, or
  # the last of the commented-on lines of a mutli-line comment.
  #
  # Returns an integer, or `nil` for an outdated comment,
  # or raises `InvalidDiffError`.
  def line
    async_line.sync
  end

  # Internal: The adjusted 1-indexed blob position of a single-line comment, or
  # the last of the commented-on lines of a mutli-line comment.
  #
  # Returns a promise resolving to an integer, or nil for an outdated comment,
  # or raises `InvalidDiffError`.
  def async_line
    async_adjusted_blob_position.then do |line|
      line + 1 if line && !outdated?
    end
  end

  # Behaves like `#async_line` for valid diffs, but returns a promise that
  # resolves to `nil` instead of raising for invalid diffs.
  def async_safe_line
    async_line.rescue do |error|
      if error.is_a?(PullRequestReviewComment::AbstractPositionData::InvalidDiffError)
        GitHub.logger.error(
          "Falied to find line number for PR review thread",
          "code.namespace": "PullRequestReviewThread",
          "code.function": "async_safe_line",
          "exception.message": error.message,
          "exception.type": error.class.name,
          "gh.repo.id": repository_id,
          "gh.pull_request.id": pull_request_id,
          "gh.pull_request_review_thread.id": id,
          "gh.pull_request_review_thread.created_at": created_at,
        )

        next nil
      end

      raise error
    end
  end

  # Behaves like `#line` for valid diffs, but returns `nil` instead of raising
  # for invalid diffs.
  def safe_line
    async_safe_line.sync
  end

  # Determines whether the given viewer can reply to this thread.
  #
  # viewer - A User or nil for a anonymous viewer.
  #
  # Returns a Promise<Boolean>.
  def async_viewer_can_reply?(viewer)
    async_viewer_cannot_reply_reasons(viewer).then(&:empty?)
  end

  def async_viewer_cannot_reply_reasons(viewer)
    return Promise.resolve([:login_required]) unless viewer

    errors = []
    errors << :verified_email_required if viewer.must_verify_email?

    Promise.all([
      async_first_comment,
      async_original_pull_request_comparison
    ]).then do |first_comment, pull_comparison|
      errors << :missing_objects unless pull_comparison
      errors << :reply if first_comment&.reply?

      async_repository.then do |repository|
        if T.must(repository).archived?
          errors << :archived
          errors
        else
          async_locked_for?(viewer).then do |locked|
            errors << :locked if locked
            errors
          end
        end
      end
    end
  end

  def async_reactions_locked_for?(actor)
    async_locked_for?(actor)
  end

  def async_locked_for?(viewer)
    async_pull_request.then { |x| T.must(x).async_issue }.then do |issue|
      issue.async_locked_for?(viewer)
    end
  end

  def resolved?
    resolver_id.present?
  end

  def async_diff_entry
    return @async_diff_entry if defined?(@async_diff_entry)

    @async_diff_entry = async_diff.then do |diff|
      next unless diff
      @diff_entry = diff[path]
    end
  end

  batch_method(:prelude_diff_lines) do |review_threads, options|
    results = Promise.all(
      review_threads.map { |thread| thread.async_diff_lines(max_context_lines: options[:max_context_lines], cache_only: !!options[:cache_only]) }
    ).sync

    review_threads.zip(results).to_h
  end

  # Public: Async load diff lines with syntax highlighting.
  #
  # max_context_lines - The Integer number of lines above the commented diff line(s)
  #                     to include for context purposes.
  # cache_only        - Determines whether or not to force reading syntax highlighted
  #                     lines from the cache or if we should also prepopulate the
  #                     cache. (optional) (default: false)
  #
  # Returns a Promise.
  def async_diff_lines(max_context_lines:, cache_only: false)
    return Promise.resolve([]) if on_file?

    Promise.all([
      async_pull_request,
      async_pull_request.then { |x| T.must(x).async_compare_repository },
      async_diff_entry,
    ]).then do |pull_request, repository, diff_entry|
      async_warm_syntax_highlighted_diff = if diff_entry && !cache_only
        Platform::Loaders::WarmSyntaxHighlightedDiffCache.load(repository, pull_request, diff_entry)
      else
        Promise.resolve(nil)
      end

      async_warm_syntax_highlighted_diff.then do
        excerpt_offset = excerpt_starting_offset(max_context_lines)
        line_enumerable = excerpt_line_enumerable.drop(excerpt_offset)

        diff_hunk_start_index = if diff_entry && line_enumerable.any?
          first_line = line_enumerable.first

          first_line_index = diff_entry.enumerator.find_index do |line|
            line.left == first_line.left && line.right == first_line.right
          end

          first_line_index - excerpt_offset if first_line_index.present?
        end

        cache_code, html_lines = SyntaxHighlightedDiff.new(repository).frozen_colorized_lines_with_cache_code(diff_entry)

        line_enumerable.map do |line|
          HighlightedDiffLine.for_line(
            line,
            html_lines: html_lines,
            offset: diff_hunk_start_index,
            cache_code: cache_code
          ).as_json
        end
      end
    end
  end

  # Public: Forked from async_diff_lines above specifically to isolate use in GraphQL
  #         api for support of file-level threads on mobile
  #
  # max_context_lines - The Integer number of lines above the commented diff line(s)
  #                     to include for context purposes.
  # cache_only        - Determines whether or not to force reading syntax highlighted
  #                     lines from the cache or if we should also prepopulate the
  #                     cache. (optional) (default: false)
  #
  # Returns a Promise.
  def async_file_level_diff_lines(max_context_lines:, cache_only: false)
    return Promise.resolve([]) unless on_file?

    Promise.all([
      async_pull_request,
      async_pull_request.then { |x| T.must(x).async_compare_repository },
      async_diff_entry,
    ]).then do |pull_request, repository, diff_entry|
      async_warm_syntax_highlighted_diff = if diff_entry && !cache_only
        Platform::Loaders::WarmSyntaxHighlightedDiffCache.load(repository, pull_request, diff_entry)
      else
        Promise.resolve(nil)
      end

      line_enumerable = T.let([], T::Array[T.untyped])
      diff_hunk_start_index = T.let(nil, T.nilable(Integer))

      async_warm_syntax_highlighted_diff.then do
        # File level comments pretend to be at the beginning of the diff
        # for the sake of clients that do not know how to handle the
        # subject_type field yet. This is only used by the mobile app and can
        # be removed when it has subject_type/FLC support.
        line_enumerable = diff_entry.enumerator.lazy
          .take(2) # hunk header plus the single line we need for position
          .to_a
        line_enumerable.shift # discard hunk header
        diff_hunk_start_index = 0

        cache_code, html_lines = SyntaxHighlightedDiff.new(repository).frozen_colorized_lines_with_cache_code(diff_entry)

        line_enumerable.map do |line|
          HighlightedDiffLine.for_line(
            line,
            html_lines: html_lines,
            offset: diff_hunk_start_index,
            cache_code: cache_code
          ).as_json
        end
      end
    end
  end

  def diff_lines_truncated?
    return false unless start_position_offset = self.start_position_offset

    start_position_offset + 1 > MAX_MULTI_LINE_EXCERPT_LINES
  end

  def async_original_pull_request_comparison
    return @async_original_pull_request_comparison if defined? @async_original_pull_request_comparison

    @async_original_pull_request_comparison = async_pull_request.then do |pull_request|
      T.must(pull_request).async_historical_comparison.then do
        # Use recorded original_base_commit_id if available, otherwise fallback to
        # guessing by recomputing the merge base from the current PR base.
        base_commit_oid  = original_base_commit_id  || T.must(pull_request).compute_base_commit_id(original_commit_id)
        start_commit_oid = original_start_commit_id || base_commit_oid
        end_commit_oid   = original_end_commit_id   || original_commit_id

        T.must(pull_request).async_pull_comparison(
          start_oid: start_commit_oid,
          end_oid: end_commit_oid,
          base_oid: base_commit_oid,
        )
      end
    end
  end

  def async_discussion_diff_path_uri
    return @async_discussion_diff_path_uri if defined?(@async_discussion_diff_path_uri)

    @async_discussion_diff_path_uri = async_pull_request.then do |pull_request|
      T.must(pull_request).async_path_uri.then do |path_uri|
        async_first_comment.then do |first_comment|
          path_uri_2 = path_uri.dup
          path_uri_2.fragment = "discussion-diff-#{first_comment.id}"
          path_uri_2
        end
      end
    end
  end

  def async_original_diff_path_uri
    async_first_comment.then(&:async_original_diff_path_uri)
  end

  def async_original_diff_file_path_uri
    return @async_original_diff_file_path_uri if defined?(@async_original_diff_file_path_uri)

    @async_original_diff_file_path_uri = async_original_diff_path_uri.then do |path_uri|
      next unless path_uri
      async_diff_file_path_uri(path_uri)
    end
  end

  def async_original_diff_file_path_with_fragment
    return @async_original_diff_path_with_fragment if defined?(@async_original_diff_path_with_fragment)

    @async_original_diff_path_with_fragment = async_original_pull_request_comparison.then do |pull_request_comparison|
      next unless pull_request_comparison

      if pull_request_comparison.range?
        "/files/#{pull_request_comparison.start_commit.oid}..#{pull_request_comparison.end_commit.oid}##{path_fragment}"
      else
        "/files/#{pull_request_comparison.end_commit.oid}##{path_fragment}"
      end
    end
  end

  def async_current_diff_path_uri
    async_first_comment.then(&:async_current_diff_path_uri)
  end

  def async_current_diff_file_path_uri
    return @async_current_diff_file_path_uri if defined?(@async_current_diff_file_path_uri)

    @async_current_diff_file_path_uri = async_current_diff_path_uri.then do |path_uri|
      next unless path_uri
      async_diff_file_path_uri(path_uri)
    end
  end

  def current_diff_file_path_with_fragment
    "/files##{path_fragment}"
  end

  def path_fragment
    @path_fragment ||= "diff-#{path_digest}"
  end

  def async_pull_request_commit
    Promise.all([
      async_pull_request,
      async_position_data.then(&:commit_oid),
    ]).then do |pull_request, commit_oid|
      pull_request.async_load_pull_request_commit(commit_oid)
    end
  end

  # Public: Returns the _original_ end blob position.
  def async_original_line
    async_position_data.then(&:line)
  end

  # Public: The original 1-indexed blob position of a single-line comment, or
  # the last of the commented-on lines of a mutli-line comment.
  #
  # Returns an integer.
  def original_line
    async_original_line.sync
  end

  # Public: Returns the _original_ start blob position (multi-line only).
  def async_original_start_line
    async_position_data.then(&:original_start_line)
  end

  # Public: The original 1-indexed blob position of the first of the
  # commented-on lines of a mutli-line comment.
  #
  # Returns an integer, or `nil` for single-line comments.
  def original_start_line
    async_original_start_line.sync if start_position_offset.present?
  end

  def async_diff_side
    async_position_data.then(&:diff_side).rescue do |error|
      GitHub.logger.error(
        "Falied to find diff side for PR review thread",
        "code.namespace": "PullRequestReviewThread",
        "code.function": "async_diff_side",
        "exception.message": error.message,
        "exception.type": error.class.name,
        "gh.repo.id": repository_id,
        "gh.pull_request.id": pull_request_id,
        "gh.pull_request_review_thread.id": id,
        "gh.pull_request_review_thread.created_at": created_at,
      )

      raise error
    end
  end

  def async_can_resolve(viewer)
    return Promise.resolve(false) if resolved?

    can_change_resolve_state(viewer)
  end

  def async_can_unresolve(viewer)
    return Promise.resolve(false) unless resolved?

    can_change_resolve_state(viewer)
  end

  def comments
    review_comments
  end

  def async_first_comment
    async_review_comments.then do |review_comments|
      T.unsafe(review_comments).sort_by(&:id).first
    end
  end

  # The condensed diff excerpt as a String.
  def excerpt(max = 15)
    return "" if on_file?
    offset = excerpt_starting_offset(max)

    if lines = diff_hunk_lines[offset..-1]
      lines.join("\n").gsub(/^~/, " ")
    else
      ""
    end
  end

  # Like excerpt but html escaped.
  def excerpt_html(max = 15)
    ERB::Util.force_escape(excerpt(max).to_s)
  end

  # Public: The positioning data for this comment.
  #
  # Returns an instance of a subclass of PullRequestReviewComment::AbstractPositionData
  # representing the positioning data of this comment.
  def position_data
    async_position_data.sync
  end

  def async_target_path(diff = nil)
    async_current_diff(diff).then do |diff|
      async_position_data.then do |position_data|
        position_data.target_path(diff, path)
      end
    end
  end

  def async_position_data
    return @async_position_data if defined?(@async_position_data)

    @async_position_data = if has_blob_positioning_data?
      PullRequestReviewComment::PositionData.async_from_thread(self)
    elsif on_file?
      PullRequestReviewComment::FileLevelPositionData.async_from_thread(self)
    else
      PullRequestReviewComment::LegacyPositionData.async_from_thread(self)
    end
  end

  def async_original_diff
    return @async_original_diff if defined? @async_original_diff

    @async_original_diff = async_pull_request.then do |pull_request|
      original_commit_oid = original_commit_id       || commit_id
      base_commit_oid     = original_base_commit_id  || T.must(pull_request).compute_base_commit_id(original_commit_oid)
      start_commit_oid    = original_start_commit_id || base_commit_oid
      end_commit_oid      = original_end_commit_id   || original_commit_oid

      T.must(pull_request).async_diff(
        start_commit_oid: start_commit_oid,
        end_commit_oid: end_commit_oid,
        base_commit_oid: base_commit_oid,
      )
    end
  end

  # Public: Given the current diff, recalculate the positioning information.
  # Note: This method does not persist the recalculated positioning information.
  def async_reposition_from_blob_position(diff = nil)
    async_current_diff(diff).then do |current_diff|
      Promise.all([
        async_pull_request,
        async_adjusted_diff_position(current_diff),
        async_adjusted_start_blob_position(current_diff),
      ]).then do |pull_request, adjusted_diff_position, adjusted_start_blob_position|
        # If this was a multiline comment and we can't calculate the start position
        # anymore, then set position to nil so the comment becomes outdated.
        if start_position_offset && adjusted_start_blob_position.nil?
          adjusted_diff_position = nil
        end

        self.position = adjusted_diff_position
        # TODO: Do we really need this `commit_id` assignment?!
        self.commit_id = pull_request.head_sha
        self.outdated = adjusted_diff_position.nil?
      end
    end
  end

  # Public: Returns the comment's adjusted start position in the blob.
  #
  # Returns a Promise resolving to an Integer or nil.
  def async_adjusted_start_blob_position(diff = nil)
    return Promise.resolve(nil) unless start_position_offset

    async_start_line(diff).then do |start_line|
      next nil unless start_line

      start_line.deletion? ? start_line.blob_left : start_line.blob_right
    end
  end

  # Public: Returns the comment's adjusted end position in the blob.
  #
  # Returns a Promise resolving to an Integer or nil.
  def async_adjusted_blob_position(diff = nil, safe: false)
    return Promise.resolve(nil) if on_file?
    async_current_diff(diff).then do |diff|
      next nil unless diff

      async_position_data.then do |position_data|
        position_data.async_adjusted_blob_position(diff).then do |adjusted_blob_position|

          # if one or both commits are corrupted or missing, etc we revert to just
          # matching the diff hunk text against the vanilla diff using the loader
          if adjusted_blob_position == :bad
            destination_path = blob_path || path
            Platform::Loaders::LegacyDiffPosition.load(diff, destination_path, diff_match_text).then do |adjusted_blob_position|
              adjusted_position_dogstats(adjusted_blob_position, algorithm: :excerpt_match)
              GitHub.logger.error(
                "Fallback to excerpt matching",
                "code.namespace": "PullRequestReviewThread",
                "code.function": "async_adjusted_blob_position",
                "exception.message": "adjusted_blob_position was :bad",
                "exception.type": "PullRequestReviewThread::BadAdjustedBlobPositionError",
                "gh.repo.id": repository_id,
                "gh.pull_request.id": pull_request_id,
                "gh.pull_request_review_thread.id": id,
                "gh.pull_request_review_thread.created_at": created_at,
              )
              adjusted_blob_position
            end.rescue do |legacy_diff_position_error|
              # Track if legacy positioning also failed.
              GitHub.dogstats.increment("diff.comments.adjusted_blob_position.excerpt_match_failed")
              GitHub.logger.error(
                "LegacyDiffPosition failed",
                "code.namespace": "PullRequestReviewThread",
                "code.function": "async_adjusted_blob_position",
                "exception.message": legacy_diff_position_error.message,
                "exception.type": legacy_diff_position_error.class.name,
                "gh.repo.id": repository_id,
                "gh.pull_request.id": pull_request_id,
                "gh.pull_request_review_thread.id": id,
                "gh.pull_request_review_thread.created_at": created_at,
              )
              raise legacy_diff_position_error
            end
          else
            adjusted_position_dogstats(adjusted_blob_position, algorithm: :blob_offsets)
            adjusted_blob_position
          end
        end
      end.rescue do |error|
        unless safe && error.is_a?(PullRequestReviewComment::AbstractPositionData::InvalidDiffError)
          raise error
        end

        # We already know we have an InvalidDiffError if we got here from the check above so logging that as
        # exception.type isn't super useful. We only raise this for two different reasons established by the message
        # in the exception so we can use that to log a more useful exception.type. The messages are either "is invalid"
        # or the moderately more useful "can't be a binary file". Re-using excpetion.type allows us to chart things in
        # Splunk more easily by only counting by the exception.type instead of also having to look at exception.message.
        exception_type = if error.message == "is invalid"
          "PullRequestReviewComment::AbstractPositionData::InvalidDiffError"
        else
          "PullRequestReviewComment::AbstractPositionData::InvalidBinaryDiffError"
        end
        GitHub.logger.error(
          "Fallback to excerpt matching",
          "code.namespace": "PullRequestReviewThread",
          "code.function": "async_adjusted_blob_position",
          "exception.message": error.message,
          "exception.type": exception_type,
          "gh.repo.id": repository_id,
          "gh.pull_request.id": pull_request_id,
          "gh.pull_request_review_thread.id": id,
          "gh.pull_request_review_thread.created_at": created_at,
        )

        destination_path = blob_path || path
        Platform::Loaders::LegacyDiffPosition.load(diff, destination_path, diff_match_text).then do |adjusted_blob_position|
          adjusted_position_dogstats(adjusted_blob_position, algorithm: :excerpt_match)
          adjusted_blob_position
        end.rescue do |legacy_diff_position_error|
          # Track if legacy positioning also failed.
          GitHub.logger.error(
            "LegacyDiffPosition failed",
            "code.namespace": "PullRequestReviewThread",
            "code.function": "async_adjusted_blob_position",
            "exception.message": legacy_diff_position_error.message,
            "exception.type": legacy_diff_position_error.class.name,
            "gh.repo.id": repository_id,
            "gh.pull_request.id": pull_request_id,
            "gh.pull_request_review_thread.id": id,
            "gh.pull_request_review_thread.created_at": created_at,
          )
          raise legacy_diff_position_error
        end
      end
    end
  end
  alias async_current_line async_adjusted_blob_position

  sig { params(diff: T.untyped).returns(Promise[[T.nilable(String), T.nilable(String)]]) }
  def async_start_and_end_path(diff = nil)
    async_current_diff(diff).then do |inner_diff|
      delta = T.let(inner_diff.delta_for_path(path), T.nilable(GitRPC::Diff::Delta))
      delta&.paths
    end
  end

  # Public: The 0-based offset into the blob for the comment's start position (multi-line only).
  #
  # Returns an Integer or nil.
  def original_start_blob_position
    diff_line = original_start_diff_line
    return nil unless diff_line

    diff_line.current - 1
  end

  # Internal: The original start diff line, extracted from the diff_hunk column.
  #
  # Returns a GitHub::Diff::Line object or nil.
  def original_start_diff_line
    return nil unless start_position_offset = self.start_position_offset

    start_line_index = -(start_position_offset + 1)
    GitHub::Diff::Enumerator.new(diff_hunk_lines).to_a[start_line_index]
  end

  # Public: Comments usually need to have their blob positions updated after force pushes
  def needs_position_update?
    pull_request = T.must(self.pull_request)

    # we are only updating previously blob positioned comments for now.
    return false unless has_blob_positioning_data?

    # never reposition if the current position is still in the PR's list of commits
    return false if pull_request.changed_commit_oids.include?(blob_commit_oid)

    if left_blob
      # If this is a comment on the left blob, it's ok if we reference the merge_base, even though
      # it isn't part of the changes.
      return false if pull_request.merge_base == blob_commit_oid

      # if the branch's merge base is lost due to a weird rebase onto a branch with no common ancestors,
      # there is nothing we can do to reposition comments on removals. Comments continue to display as long
      # as the blob_commit_oid is not GC'd and the line is still present, but removed in the displayed diff.
      if pull_request.merge_base.nil?
        GitHub.dogstats.increment("pull_request_review_comments.positioning_error", tags: ["no_merge_base"])
        return false
      end
    end

    true
  end

  # Public: Updates the blob positioning columns to valid values for the PR.
  #   Only update positioning if we found a new position. Otherwise, continue
  #   pointing to the potentially orphaned commit. Maybe a future force push will
  #   allow us to reposition this comment.
  def update_position_data

    return if position_data.nil?
    diff = T.must(pull_request).historical_comments_diff
    data = position_data.adjusted_data(diff)
    data&.update_thread_position_attributes!(self)

  rescue PullRequestReviewComment::BadDiffHunkError => e
    # Not sure how this would ever happen. But if it does, let's log it and not try to
    # do this again by putting some default values in so that blob_position_lost? is true.
    Failbot.report(e, "gh.comment.id": id)
    self.blob_commit_oid = T.must(pull_request).head_sha
    self.blob_path = path
  end

  # Updates the row with the recalculated position and commit_id
  def save_positions(skip_blob_fields: false)
    if has_changes_to_save?
      # Some validations are expensive and this method is called in bulk.
      #
      # Additionally, validation flow in this model for standard create/update
      # paths is convoluted for uhh, reasons.
      #
      # Therefore, just do a quick manual validation of the attributes being changed here.
      unless position.nil? || position.is_a?(Integer)
        errors.add(:position, "must be nil or an Integer")
      end

      unless GitRPC::Util.valid_full_oid?(commit_id)
        errors.add(:commit_id, "must be a 40 character SHA1")
      end

      if errors.any?
        Failbot.report(ActiveRecord::RecordInvalid.new(self))
        return
      end

      data = {
        position:   position,
        outdated:   outdated,
        commit_id:  commit_id,
        updated_at: current_time_from_proper_timezone,
      }

      unless skip_blob_fields
        data.merge!({
          blob_commit_oid:  blob_commit_oid,
          blob_path:        blob_path,
          blob_position:    blob_position,
          left_blob:        left_blob,
        })
      end
      PullRequestReviewThread.no_touching do
        assign_attributes(data)
        save(validate: false)
      end
    end
  end

  def async_selection_contains_deletions
    return Promise.resolve(true) if left_blob?

    async_adjusted_selected_lines.then do |lines|
      lines.any? { |c| c.type == :deletion }
    end
  end

  def selection_contains_deletions?
    async_selection_contains_deletions.sync
  end

  # Public: the side of the diff to which a single-line comment or the last of
  # the commented lines of a multi-line comment applies.
  #
  # Returns `:left` for deletions or `:right` for additions and context.
  def side
    left_blob? ? :left : :right
  end
  alias_method :end_side, :side

  def original_selection

    if start_position_offset.present?
      start_line_index = -(T.must(start_position_offset) + 1)
      diff_hunk_lines[start_line_index..-1] || []
    else
      Array.wrap(diff_hunk_lines.last)
    end
  end

  def diff_entry
    return @diff_entry if defined?(@diff_entry)

    @diff_entry = load_diff_entry
  end

  def async_diff
    return @async_diff if defined?(@async_diff)

    @async_diff = async_original_pull_request_comparison.then do |pull_request_comparison|
      next unless pull_request_comparison

      Platform::Loaders::PullRequestDiff.load(pull_request_comparison.pull,
        start_commit_oid: pull_request_comparison.start_commit.oid,
        end_commit_oid: pull_request_comparison.end_commit.oid,
        base_commit_oid: pull_request_comparison.base_commit.oid,
      )
    end
  end

  def current_diff_entry
    return @current_diff_entry if defined?(@current_diff_entry)
    @current_diff_entry = load_current_diff_entry
  end

  # Public: Prepare the diff for this comment specifically. Sets the path so we support diffs
  #         beyond the max files limit, and the overrides the lines and byte limit in the case
  #         the user clicked "load diff" for a skipped file. Should ONLY be used for comment
  #         create methods, when it is ok for the diff to only be on one file.
  def preload_original_diff
    return if original_pull_request_comparison.nil?

    diff = original_pull_request_comparison.diffs
    diff.add_path(path)
    diff.maximize_single_entry_limits!
  rescue GitRPC::Error => e
    # preload just doesn't happen in this case. Optimizations are not completed.
  end

  def load_diff_entry
    return unless comparison = original_pull_request_comparison
    diffs = comparison.diffs
    return unless diffs.load_diff
    diffs[path]
  end

  def load_current_diff_entry
    diffs = T.must(pull_request).build_comparison(head_commit_oid: commit_id).diffs
    return if !diffs.available?
    diffs[path]
  end

  def current_comparison
    return @current_comparison if defined?(@current_comparison)
    @current_comparison = original_pull_request_comparison
  end

  # Public: Get PR comparison for original comment location.
  #
  # Returns PullRequest::Comparison or nil if the comparison objects can't be found.
  def original_pull_request_comparison
    async_original_pull_request_comparison.sync
  end

  def async_commit
    async_load_commit(oid: commit_id)
  end

  def async_original_commit
    async_load_commit(oid: original_commit_id)
  end

  def current_line
    async_adjusted_blob_position.sync
  end

  def current_line_range
    first_line = current_line - start_position_offset.to_i
    (first_line..current_line)
  end

  def has_blob_positioning_data?
    blob_position.present? && blob_path.present? && blob_commit_oid.present?
  end

  # The lines in the diff hunk text. Memoized because it's used in a number of
  # places, including the views that show excerpts.
  sig { returns(T::Array[String]) }
  def diff_hunk_lines
    @diff_hunk_lines ||= begin
      return [] if diff_hunk.nil?
      diff_hunk.scrub!.split("\n")
    end
  end

  def live?
    !outdated?
  end

  # Not-so-Internal: Is the diff excerpt truncated?
  def excerpt_truncated?
    return false unless start_position_offset = self.start_position_offset

    start_position_offset + 1 > MAX_MULTI_LINE_EXCERPT_LINES
  end

  # Determine whether the changed lines continue after the diff_hunk_lines. If so,
  # the check for related lines may be unreliable.
  #
  # Returns true if the diff hunk is truncated, false if not.
  def diff_hunk_is_truncated?
    if index = end_of_diff_hunk
      next_line_prefix = diff_entry.text[index + 1]
      next_line_type   = GitHub::Diff::Enumerator.line_type(next_line_prefix)

      next_line_type == :addition || next_line_type == :deletion
    else
      false
    end
  end

  def destroy_if_empty
    destroy if review_comments.empty?
  end

  # The range of context lines requested for an outside the diff comment.
  def blob_context_line_range
    blob_position = T.must(self.blob_position)
    Range.new(
      (original_start_blob_position || blob_position) - (OUTSIDE_DIFF_CONTEXT_MARGIN - 1),
      blob_position + (OUTSIDE_DIFF_CONTEXT_MARGIN) + 1
    )
  end

  def outside_diff?
    return unless diff_hunk

    self.diff_hunk.split("\n").any? do |line|
      return true if line.first == "~" && !outdated?
    end

    false
  end

  # Public: Returns the diff-relative position for an async instance of this thread
  # and the passed viewer as determined by the pull request's current pull_comparison
  #
  # Examples
  #
  #   pull_request_review_thread.async_diff_relative_position_for_viewer(viewer: viewer)
  #
  # Returns an Integer or nil

  def async_diff_relative_position_for_viewer(viewer:)
    async_repository.then do |_respository|

      # once this feature flag is removed, this can be refactored to no longer
      # loop through the async_repo or return self.position

      if comment_outside_diff_enabled?
        async_pull_request.then do |pull_request|
          T.must(pull_request).async_diff_relative_position_for_thread_id_with_viewer(
            thread_id: id,
            viewer: viewer
          )
        end
      else
        position
      end
    end
  end

  def comment_outside_diff_enabled?
    return @comment_outside_diff_enabled if defined?(@comment_outside_diff_enabled)
    @comment_outside_diff_enabled = GitHub.flipper[:comment_outside_the_diff].enabled?(T.cast(repository, T.nilable(Repository))) # rubocop:todo GitHub/AvoidCast
  end

  # Public: returns whether a file with this thread's path is missing
  # from either the diff or diff summary specified.
  # Used when initially saving threads, when repositioning comments, and
  # by the ThreadPositioner to determine if a thread should be marked as
  # outdated.
  def file_level_thread_outdated_as_of_diff?(diff: nil, summary: nil)
    raise ArgumentError, "Only used with file-level threads" unless on_file?
    raise ArgumentError, "Must provide either diff or summary" if diff.nil? && summary.nil?
    if diff
      now_outdated = diff.entries.detect do |entry|
        if left_blob
          entry.a_path == path
        else
          entry.b_path == path
        end
      end.nil?
    else
      now_outdated = summary.detect do |delta|
        if left_blob
          delta.old_file.path == path
        else
          delta.new_file.path == path
        end
      end.nil?
    end
  end

  def path_digest
    @path_digest ||= Digest::SHA256.hexdigest(path)
  end

  # Public: Assigns diff attributes to this thread as if building a first comment via the `build_first_comment`
  # method above
  #
  # user - the User who commented. Defaults to the writer of the review
  # body - the String body of the comment
  # path - the path of the right side of the diff entry on which the comment has been left
  # diff - the GitHub::Diff on which this comment has been left. Defaults to the latest diff for the pull request.
  # start line & side - The start line of a multi line comment and the side of the diff it is on.
  # line & side - The line and side of the comment. The end of the range for a multi-line comment.

  def assign_path_and_position_attributes(
      user: T.must(pull_request_review).user,
      body:,
      path:,
      diff: nil,
      start_line: nil,
      start_side: :right,
      line: nil,
      side: :right
    )

    self.path ||= path

    diff ||= T.must(pull_request).historical_comparison.diffs
    diff = diff.only_params

    if on_file?
      self.left_blob = side.to_sym == :left
      self.end_position_data = PullRequestReviewComment::FileLevelPositionData.async_from_thread(self, diff: diff).sync
    else
      self.start_position_data = diff_position_data(diff, path, start_side, start_line)
      self.end_position_data = diff_position_data(diff, path, side, line)
    end
  end

  private

  def reset_memoized_attributes
    remove_instance_variable(:@async_adjusted_selected_lines) if defined?(@async_adjusted_selected_lines)
  end

  def should_ensure_synced_with_pull_request?
    return if on_file?
    return if importing_historical_thread?

    true
  end

  def should_validate_original_position?
    return if on_file?
    return if end_position_data.present?

    true
  end

  # Iterate over lines in the diff hunk with line type, number, and position
  # tracking.
  #
  # Returns a GitHub::Diff::RelatedLinesEnumerator object whose each method
  # yields a [type, text, position, left, right, current, related] tuple. See
  # Diff::RelatedLinesEnumerator for details on the individual tuple elements.
  def excerpt_line_enumerable
    if diff_hunk_is_truncated?
      GitHub::Diff::Enumerator.new(diff_hunk_lines)
    else
      GitHub::Diff::RelatedLinesEnumerator.new(diff_hunk_lines)
    end
  end

  # The zero-based line offset into the diff hunk text where the condensed
  # excerpt starts. The excerpt includes the last pair of insertions/deletions
  # with surrounding context up to the maximum number of lines specified.
  #
  # max - The maximum number of adjacent insertion/deletion lines to
  #       include in the excerpt. The actual number of lines may be more
  #       because surrounding context is always included.
  #
  # Returns the integer offset into the diff_hunk_links array where the
  #   excerpt starts.
  def excerpt_starting_offset(max)
    if start_position_offset = self.start_position_offset
      return diff_hunk_lines.size - [MAX_MULTI_LINE_EXCERPT_LINES, start_position_offset + 1, diff_hunk_lines.size].min
    end

    offset = diff_hunk_lines.size - 1

    context = T.let(false, T::Boolean)
    modified = 0
    while offset > 0
      line = T.must(diff_hunk_lines[offset])
      case line[0]
      when "-", "+", "~"
        if context
          offset += 1
          break
        end
        modified += 1
      when "@"
        break
      else
        context = true if modified > 0
      end
      break if modified > max
      offset -= 1
    end
    [offset, 0].max
  end

  def importing_historical_thread?
    importing? && diff_hunk.present? && position.present? && outdated
  end

  def instrument_creation
    instrument :create
    GlobalInstrumenter.instrument("pull_request_review_thread.create", {
      pull_request_review_thread: self,
      repository: repository,
    })
  end

  def instrument_deletion
    # If the destruction is happening as part of repo archiving
    # then there will be a lot of nil references during the destruction
    # and there will be no useful instrumentation data to store.
    return if repository.nil?

    instrument :delete
    GlobalInstrumenter.instrument("pull_request_review_thread.delete", {
      pull_request_review_thread: self,
      repository: repository,
    })
  end

  def async_load_commit(oid:)
    return Promise.resolve(nil) unless [commit_id, original_commit_id].include?(oid)

    async_pull_request.then do |pull_request|
      Promise.all([
        T.must(pull_request).async_repository,
        T.must(pull_request).async_head_repository,
        T.must(pull_request).async_base_repository,
      ]).then do |repository, head_repository, base_repository|
        Platform::Loaders::GitObject.load(repository, oid, alternate_repositories: [head_repository, base_repository], expected_type: :commit)
      end
    end
  end

  def position_for_diff(diffs, current)
    return nil if diffs.ignore_whitespace?

    if current
      position
    else
      calculate_position_on_diff(diffs)
    end
  end

  def calculate_position_on_diff(diffs)
    return if on_file?
    new_position = position

    if diff = diffs[path]
      diff_text = diff.text.to_s.b + "\n"
      match_text = diff_match_text.b
      if offset = diff_text.index(match_text)
        lines = diff_text[0, offset + match_text.size].split("\n")
        new_position = lines.size - 1
      else
        # original diff text not found in new diff. comment is dead.
        new_position = nil
      end
    else
      # file was removed
      new_position = nil
    end

    new_position
  end

  # Text to locate in the changed diff to reposition the comment. The current
  # implementation uses the last five lines of the original diff hunk.
  #
  # The ending newline is to keep from matching when the last line has
  # text added to it.
  def diff_match_text
    buf = []
    pos = diff_hunk_lines.size - 1
    while pos > 0
      line = T.must(diff_hunk_lines[pos])
      break if line[0] == "@"
      break if buf.size >= 5
      buf.unshift(line)
      pos -= 1
    end
    buf.join("\n") + "\n"
  end

  # Find the index in the diff entry text where this diff hunk ends. This may
  # not be available if the diff entry can't be loaded or if the base branch
  # has been force-pushed.
  #
  # Returns the Integer string index, or nil if the index can't be determined.
  def end_of_diff_hunk
    return nil unless original_position = self.original_position
    return nil unless diff_entry && diff_entry.text && original_position

    diff_entry_text = diff_entry.text
    index = T.let(-1, T.nilable(Integer))

    (original_position + 1).times do
      index = diff_entry_text.index("\n", T.must(index) + 1)
      return if index.nil?
    end
    index
  end

  # Protected: The commit_id and position are updated when new commits are pushed to the
  # pull request. Maintain the original commit_id and position so we can locate
  # the original diff hunk if necessary.
  #
  # Fired before_validation on_create
  def initialize_original_attribute_values
    self.original_commit_id ||= commit_id
    self.original_base_commit_id ||= T.must(pull_request).compute_base_commit_id(original_commit_id)
    self.original_start_commit_id ||= original_base_commit_id
    self.original_end_commit_id ||= original_commit_id
    self.original_position ||= position if !on_file?
  end

  def write_start_position_offset
    return unless start_position_data

    self.start_position_offset = start_position_data.calculate_start_position_offset(end_position_data)
  end

  def write_end_position_attributes
    end_position_data&.write_thread_end_position_attributes!(thread: self)
  end

  # initialize blob positioning attributes.  Fired before_create
  def initialize_end_position_data
    self.end_position_data ||= position_data
  end

  # Private: new review comments that are not replies to another comment get created with
  # the commit_id, path and position of the diff hunk that the user was looking
  # at when they wrote the comment. that's great - we need that info to look up
  # the hunk that the user was talking about.
  #
  # the problem is that the head of the pull request might now be different
  # than what was in the users browser when they made the comment. we need to
  # check if the head_sha of the pull has changed and recalculate the comment
  # position if so, making sure that it doesn't change yet again underneath
  # us while we do that.
  #
  # We should only attempt to reposition the comments if the head SHA of the PR
  # has changed from the review's head SHA. It's possible the PR's head SHA will
  # change again while we're updating the positions, so we will attempt this up
  # to 3 times.
  def ensure_synced_with_pull
    outdated = T.let(false, T::Boolean)

    GitHub.dogstats.time("pull_request_review_comment", tags: ["action:ensure_synced_with_pull"]) do
      position_was = position
      attempt = 1
      pr_head_sha = PullRequest.where(id: pull_request_id, repository_id:).pick(:head_sha)

      while pr_head_sha != commit_id
        async_reposition_from_blob_position.sync
        outdated = true if position_was.present? && position.nil?
        save_positions(skip_blob_fields: true)

        # Attempt to acquire an exclusive lock on the PR record
        rows_touched = PullRequest.where(id: pull_request_id, repository_id:, head_sha: pr_head_sha).touch_all

        pull_request_locked = rows_touched.nonzero?

        if pull_request_locked
          # Succesfully repositioned: PR record is locked until the end of
          # this DB transaction.
          GitHub.dogstats.increment(
            "pull_request_review_thread.ensure_synced_with_pull.repositioned",
            tags: ["result:success", "attempts:#{attempt}"]
          )
          break
        elsif attempt < 3
          # PR head has moved: we need to try again
          attempt += 1
          pr_head_sha = PullRequest.where(id: pull_request_id, repository_id:).pick(:head_sha)
        else
          # PR head has moved too many times in rapid succession for us to keep
          # up: bail out by raising an exception.
          GitHub.dogstats.increment(
            "pull_request_review_thread.ensure_synced_with_pull.repositioned",
            tags: ["result:failure", "attempts:#{attempt}"]
          )
          raise PositionSyncError.new(
            "Failed to ensure new review comment position is in sync with PR"
          )
        end
      end
    end

    GitHub.dogstats.increment("pull_request.sync.position_outdated", tags: ["blob_position:false"]) if outdated
  end

  # File-level comments only become outdated if the pull request has been
  # updated such that the diff no longer includes the file being commented on
  # LOCK IN SHARE MODE allows the row to be read by other connections but not
  # updated or deleted. This means that if the PR gets pushed to while we're in
  # here and tries to update the head_sha, it will wait for us to finish.
  def ensure_file_part_of_diff
    transaction do
      PullRequest.connection.select_rows(Arel.sql(<<-SQL, pull_request_id: pull_request_id))
        SELECT * FROM pull_requests WHERE id = :pull_request_id LOCK IN SHARE MODE
      SQL
      self.pull_request = PullRequest.find(pull_request_id)
      pull_request = T.must(self.pull_request)
      diff_summary = T.unsafe(pull_request.head_repository).rpc.native_read_diff_toc_with_base(pull_request.merge_base, pull_request.head_sha, pull_request.base_sha)
      now_outdated = file_level_thread_outdated_as_of_diff?(summary: diff_summary)
      update(outdated: now_outdated, commit_id: pull_request.head_sha)
    end
  end

  def validate_end_position_data
    return unless end_position_data

    message = "is not part of the pull request"

    error_promise = async_pull_request.then { |x| T.must(x).async_historical_comparison }.then do |comparison|
      Promise.all([
        comparison.async_covers_commit?(end_position_data.diff.sha1),
        comparison.async_covers_commit?(end_position_data.diff.sha2),
      ]).then do |start_present, end_present|
        errors.add(:start_commit_oid, message) unless start_present
        errors.add(:end_commit_oid, message) unless end_present

        if base_commit_oid = end_position_data.diff.base_sha
          errors.add(:base_commit_oid, "could not be found") unless GitRPC::Util.valid_full_oid?(base_commit_oid)

          comparison.async_load_commits([base_commit_oid]).then do |commits|
            errors.add(:base_commit_oid, "could not be found") if commits.first.nil?
          end
        end
      end
    end

    error_promise.sync

    return errors unless errors.empty?

    begin
      if end_position_data.diff_entry.too_big?
        errors.add(:path, "diff too large") unless on_file?
      end
    rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError, PullRequestReviewComment::AbstractPositionData::InvalidPathError => e
      errors.add :path, e.message
    end

    return unless errors.empty?

    valid_position = begin
      end_position_data.adjustment_blob_position_valid?
    rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError
      false
    end

    unless on_file?
      unless valid_position
        if end_position_data.is_a?(PullRequestReviewComment::LegacyPositionData)
          errors.add(:position, "is invalid")
        else
          errors.add(:line, "required and an integer greater than zero")
        end
      end

      if valid_position && !end_position_data.diff_position
        if end_position_data.is_a?(PullRequestReviewComment::LegacyPositionData)
          errors.add(:position, "is invalid")
        else
          errors.add(:line, "must be part of the diff")
        end
      end
    end
  end

  def validate_start_position_offset
    return unless start_position_data
    return if errors.include?(:path)
    start_position_offset = self.start_position_offset

    if start_position_offset.nil?
      errors.add(:start_line, "must be part of the same hunk as the line.")
    elsif start_position_offset >= diff_hunk_lines.length
      # We only extract the diff hunk up to the first hunk header, so if we've
      # computed an offset that's equal to or greater than the extracted lines,
      # it's because it crosses a hunk header boundary.
      errors.add(:start_line, "must be part of the same hunk as the line.")
    elsif start_position_offset < 1
      errors.add(:start_line, "must precede the end line.")
    end
  end

  # Internal: The current diff we'll use to calculate positioning information.
  # Default's to the pull request's `current_comments_diff`.
  #
  # Returns a Promise resolving to a GitHub::Diff object.
  def async_current_diff(diff = nil)
    return Promise.resolve(diff) if diff

    if creation_diff
      diff = creation_diff.only_params
      diff.add_paths([path])
      diff.maximize_single_entry_limits!
      Promise.resolve(diff)
    else
      async_pull_request.then { |x| T.must(x).async_current_threads_diff }
    end
  end

  # Internal: Given the current diff, find the adjusted end position of the
  # comment in the diff.
  def async_adjusted_diff_position(diff = nil)
    # just return the "current" diff position for nil (default) diff
    return Promise.resolve(position) if diff.nil?

    Promise.all([
      async_adjusted_blob_position(diff, safe: true),
      async_adjusted_path(diff), #TODO: can this be cached? It's probably used in async_adjusted_blob_position too.
    ]).then do |adjusted_blob_position, adjusted_path|
      diff.position_for(adjusted_blob_position, adjusted_path, left_blob)
    end
  end

  def async_adjusted_selected_lines(diff = nil)
    return @async_adjusted_selected_lines[diff] if defined? @async_adjusted_selected_lines

    @async_adjusted_selected_lines = Hash.new do |hash, key|
      offset = start_position_offset || 0

      hash[key] =
        async_current_diff(key).then do |current_diff|
          next [] unless current_diff

          async_adjusted_diff_position(current_diff).then do |diff_position|
            next [] unless diff_position

            async_adjusted_path(current_diff).then do |path|
              selected_lines = selected_lines_for(diff_position, path, current_diff)

              # Does the extracted diff hunk, from the end position to the start
              # position, match the content of the provided diff across the same line range?
              next [] unless selected_lines.map(&:text) == diff_hunk_lines.last(offset + 1)

              selected_lines
            end
          end
        end
    end
    @async_adjusted_selected_lines[diff]
  end

  # Internal: Given the current diff, find the adjusted path for the comment.
  def async_adjusted_path(diff)
    async_current_diff(diff).then do |current_diff|
      async_position_data.then do |position_data|
        begin
          position_data.adjustment_parameters(current_diff, caller: "pull_request_review_thread.async_adjusted_path")[:destination][:path].dup.force_encoding(Encoding::UTF_8)
        rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError
          position_data.comment_path
        end
      end
    end
  end

  # Internal: The selected diff lines for the comment in the provided diff.
  #
  # Returns an Array of GitHub::Diff::Line objects, or an empty Array.
  def selected_lines_for(position, path, diff)
    offset = start_position_offset || 0

    entry = diff[path]
    return [] unless entry

    range_start = position - offset
    return [] unless range_start > 0

    entry.enumerator.each_with_object([]) do |diff_line, lines|
      break lines if diff_line.position > position

      if (range_start..position).include?(diff_line.position)
        lines << diff_line
      end
    end
  end

  def adjusted_position_dogstats(adjusted_blob_position, algorithm:)
    outdated = adjusted_blob_position.nil? ? "true" : "false"
    tags = ["algorithm:#{algorithm}", "outdated:#{outdated}"]
    GitHub.dogstats.increment("diff.comments.adjusted_blob_position", tags: tags)
  end

  def can_change_resolve_state(viewer)
    return Promise.resolve(false) if viewer&.spammy?

    async_pull_request_review.then do |_review|
      if published?
        async_pull_request.then do |pull|
          Promise.all([T.must(pull).async_user, T.must(pull).async_repository]).then do |pr_author, repo|
            next false unless conversation?
            next true if pr_author && viewer == pr_author

            repo.async_writable_by?(viewer)
          end
        end
      else
        Promise.resolve(false)
      end
    end
  end

  def async_diff_file_path_uri(diff_path_uri)
    Promise.resolve(diff_path_uri.dup.tap { |uri| uri.fragment = path_fragment })
  end

  def diff_position_data(diff, path, side, line)
    return nil if line.nil?

    PullRequestReviewComment::DiffPositionData.new(
      diff: diff,
      line: line,
      right_path: path,
      side: side,
    )
  end

  def legacy_position_data(diff, path, position)
    PullRequestReviewComment::LegacyPositionData.new(
      diff: diff,
      comment_path: path,
      diff_position: position,
    )
  end

  def truncate_diff_hunk
    return unless self.diff_hunk
    if self.diff_hunk.bytesize > MYSQL_UNICODE_BLOB_LIMIT
      self.diff_hunk.force_encoding("binary")
      self.diff_hunk = self.diff_hunk[0...MYSQL_UNICODE_BLOB_LIMIT]
      GitHub.dogstats.increment("pull_request_review_thread.diff_hunk.truncated")
    end
  end

  def set_repository_id
    self.repository_id = T.must(pull_request).repository_id
  end

  def event_payload
    {
      pull_request_review_thread_id: id,
      repository: repository,
      repo: T.must(repository).name_with_display_owner,
      pull_request_id: pull_request_id,
    }
  end
end
