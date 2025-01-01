# typed: true
# frozen_string_literal: true

class CreateNewPullRequestReviewCommentOrchestration < PullRequestReviewCommentOrchestration
  include PullRequests::Orchestrations::DataAttributes

  def only_save_on_orchestration_end? = true

  data :actor, User
  data :body, String, persisted: false
  data :diff_start_commit_oid, String, required: false
  data :diff_end_commit_oid, String, required: false
  data :diff_base_commit_oid, String, required: false
  data :line, Integer, required: false
  data :path, String
  data :review, PullRequestReview
  data :side, Symbol, default: :right, required: false
  data :start_line, Integer, required: false
  data :start_side, Symbol, default: :right, required: false
  data :subject_type, Symbol, default: :line, required: false
  data :submit_review, Types::Boolean, default: false, required: false

  sig { returns(GitHub::Diff) }
  attr_reader :diff

  sig { returns(PullRequestReview) }
  def public_review
    review
  end

  sig { returns(PullRequestReviewComment) }
  def comment
    @comment ||= self.pull_request_review_comment
  end

  sig { returns(PullRequestReviewThread) }
  attr_reader :thread

  sig { returns(PullRequest) }
  def pull_request!
    T.must(pull_request)
  end

  sig { returns(T.nilable(String)) }
  def merge_base
    pull_request!.merge_base
  end

  sig { returns(Repository) }
  def head_repository
    @head_repository ||= pull_request!.head_repository
  end

  sig { returns(Issue) }
  def issue
    @issue ||= pull_request!.issue
  end

  sig { returns(T::Hash[String, T::Array[T::Range[Integer]]]) }
  def context_lines
    @context_lines ||= begin
      return {} unless head_repository.feature_enabled?(:comment_outside_the_diff)
      return {} unless subject_type == :line
      return {} if line.nil?

      range_start = start_line ? start_line : line
      range_end = line

      if range_start && range_end
        { path => [Range.new(range_start - 4, range_end + 6)] }
      else
        {}
      end
    end
  end

  # ------------------------------------------------------------
  #### Object initialization
  # ------------------------------------------------------------

  step :initialize_base_objects do
    @thread = PullRequestReviewThread.new
    @comment = PullRequestReviewComment.new
  end

  # ------------------------------------------------------------
  #### Orchestration validation
  # ------------------------------------------------------------

  step :validate_creator_is_authorized_to_comment do
    if pull_request!.blocked_from_reviewing?(actor)
      errors.add(:base, "Failed to create comment: User is blocked")

      # explicitly failing here because user being blocked failure is
      # a security concern
      return :failed, "Failed to create comment: User is blocked"
    end

    authorization = ContentAuthorizer.authorize(
      actor,
      :pull_request_comment,
      :create,
      issue: issue,
      repo: repository
    )

    if authorization.failed?
      comment.errors.add(:base, authorization.error_messages)

      # rubocop:disable Style/RedundantReturn
      return :failed, "Failed to create comment: #{authorization.error_messages}."
    end
  end

  step :validate_orchestration_can_proceed do
    validate_merge_base
    validate_pull_request_head_repository
    validate_pull_request_lock
    validate_review_is_pending

    return :skipped, errors.first.full_message if errors.present?
  end

  # ------------------------------------------------------------
  #### Orchestration object population
  # ------------------------------------------------------------

  step :initialize_diff do
    base_commit_oid = diff_base_commit_oid || merge_base
    start_commit_oid = diff_start_commit_oid || merge_base
    end_commit_oid = diff_end_commit_oid || pull_request!.head_sha

    if end_commit_oid.nil?
      return :failed, "Invalid commit positioning data"
    end

    pr = pull_request!

    @diff ||= GitHub::Diff.new(
      pr.compare_repository,
      start_commit_oid,
      end_commit_oid,
      base_sha: base_commit_oid,
      context_lines: context_lines,
      base_repository: pr.base_repository,
      head_repository: pr.head_repository,
    )
  end

  step :populate_thread do
    return unless repository = self.repository

    thread.assign_attributes(
      subject_type: subject_type,
      pull_request_review: review,
      pull_request: pull_request!,
      repository_id: repository.id
    )

    thread.creation_diff = diff if repository.feature_enabled?(:comment_outside_the_diff)
    thread.skip_create_callbacks = true
  end

  step :populate_comment do
    comment.assign_attributes(
      body: body,
      pull_request: pull_request!,
      pull_request_review: review,
      repository:,
      user: actor,
    )

    comment.skip_create_callbacks = true
  end

  # ------------------------------------------------------------
  #### Thread attribute initialization and calculation
  # ------------------------------------------------------------

  step :assign_position_attributes_to_thread do
    thread.assign_path_and_position_attributes(
      user: actor,
      diff: diff,
      body: body,
      path: path,
      line: line,
      side: side,
      start_line: start_line,
      start_side: start_side
    )
  end

  step :initialize_end_position_data_for_thread do
    return if thread.end_position_data

    async_position_data = begin
      if thread.blob_position.present? && thread.blob_path.present? && thread.blob_commit_oid.present?
        PullRequestReviewComment::PositionData.async_from_thread(thread)
      elsif thread.on_file?
        PullRequestReviewComment::FileLevelPositionData.async_from_thread(thread)
      else
        PullRequestReviewComment::LegacyPositionData.async_from_thread(thread)
      end
    end

    thread.end_position_data = async_position_data.sync
  end

  step :write_end_position_attributes_for_thread do
    thread.end_position_data&.write_thread_end_position_attributes!(thread: thread)
  end

  step :initialize_original_attribute_values_for_thread do
    thread.original_commit_id ||= thread.commit_id
    pull_request!.compute_base_commit_id(thread.original_commit_id)
    thread.original_start_commit_id ||= thread.original_base_commit_id
    thread.original_end_commit_id ||= thread.original_commit_id
    thread.original_position ||= thread.position if !thread.on_file?
  end

  # ------------------------------------------------------------
  #### Thread attribute validation and persistence
  # ------------------------------------------------------------

  step :write_start_position_offset_for_thread do
    return unless thread.start_position_data

    thread.start_position_offset = thread.start_position_data.calculate_start_position_offset(thread.end_position_data)
  end

  step :truncate_diff_hunk_for_thread do
    return unless thread.diff_hunk

    if thread.diff_hunk.bytesize > MYSQL_UNICODE_BLOB_LIMIT
      thread.diff_hunk.force_encoding("binary")
      thread.diff_hunk = thread.diff_hunk[0...MYSQL_UNICODE_BLOB_LIMIT]
      GitHub.dogstats.increment("pull_request_review_thread.diff_hunk.truncated")
    end
  end

  step :validate_end_position_data_in_comparison_for_thread do
    return unless thread.end_position_data
    return unless end_position_diff = thread.end_position_data&.diff

    message = "is not part of the pull request"

    comparison = pull_request!.historical_comparison

    unless comparison.async_covers_commit?(end_position_diff.sha1).sync
      thread.errors.add(:start_commit_oid, message)
    end

    unless comparison.async_covers_commit?(end_position_diff.sha2).sync
      thread.errors.add(:end_commit_oid, message)
    end

    base_commit_oid = end_position_diff.base_sha

    unless GitRPC::Util.valid_full_oid?(base_commit_oid)
      thread.errors.add(:base_commit_oid, "could not be found")
    end

    if comparison.async_load_commits([base_commit_oid]).sync.first.nil?
      thread.errors.add(:base_commit_oid, "could not be found")
    end

    skip_for_thread_validation_failure
  end

  step :validate_end_position_diff_entry_size_for_thread do
    begin
      if thread.end_position_data.diff_entry.too_big?
        thread.errors.add(:path, "diff too large") unless thread.on_file?
      end
    rescue PullRequestReviewComment::AbstractPositionData::InvalidPathError => e
      thread.errors.add(:path, e.message)
    rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError => e
      thread.errors.add(:diff, e.message)
    rescue GitRPC::ObjectMissing => e
      thread.errors.add(:gitrpc, e.message)
      thread.errors.add(:oid, "oid is not part of the pull request")
    end

    skip_for_thread_validation_failure
  end

  step :validate_end_position_data_for_line_level_thread do
    thread_has_valid_position = begin
      thread.end_position_data.adjustment_blob_position_valid?
    rescue PullRequestReviewComment::AbstractPositionData::InvalidDiffError
      false
    end

    if thread.on_line?
      unless thread_has_valid_position
        if thread.end_position_data.is_a?(PullRequestReviewComment::LegacyPositionData)
          thread.errors.add(:position, "is invalid")
        else
          thread.errors.add(:line, "required and an integer greater than zero")
        end
      end

      if thread_has_valid_position && !thread.end_position_data.diff_position
        if thread.end_position_data.is_a?(PullRequestReviewComment::LegacyPositionData)
          thread.errors.add(:position, "is invalid")
        else
          thread.errors.add(:line, "must be part of the diff")
        end
      end
    end

    skip_for_thread_validation_failure
  end

  step :validate_start_position_offset_for_thread do
    return unless thread.start_position_data

    offset = thread.start_position_offset

    if offset.nil?
      thread.errors.add(:start_line, "must be part of the same hunk as the line")
    elsif offset >= thread.diff_hunk_lines.length
      # We only extract the diff hunk up to the first hunk header, so if we've
      # computed an offset that's equal to or greater than the extracted lines,
      # it's because it crosses a hunk header boundary.
      thread.errors.add(:start_line, "must be part of the same hunk as the line")
    elsif offset < 1
      thread.errors.add(:start_line, "must precede the end line")
    end

    skip_for_thread_validation_failure
  end

  step :validate_thread_attributes do
    return unless thread.on_line?

    unless thread.compressed_diff_hunk &&
      thread.compressed_diff_hunk.to_s.encoding == ::Encoding::UTF_8 &&
      thread.compressed_diff_hunk.to_s.valid_encoding?

      thread.errors.add(:base, "Compressed diff hunk does not have valid encoding")
    end

    if thread.diff_hunk.nil?
      thread.errors.add(:base, "Diff hunk is nil")
    end

    if !thread.end_position_data.present? && thread.original_position.nil?
      thread.errors.add(:base, "Original position is nil")
    end

    skip_for_thread_validation_failure
  end

  step :persist_thread do
    thread.save

    fail_on_thread_errors
  end

  # ------------------------------------------------------------
  #### Comment attribute calculation and persistence
  # ------------------------------------------------------------

  step :validate_attributes_for_comment do
    unless comment.body.present?
      comment.errors.add(:body, "can't be blank")
    end

    unless comment.state.present?
      comment.errors.add(:state, "does not exist")
    end

    if comment.body && comment.body.bytesize > MYSQL_UNICODE_BLOB_LIMIT
      comment.errors.add(:body, "bytesize is larger than MYSQL unicode blob limit")
    end

    if comment.errors.any?
      comment.instrument(:validation_failed)
      # rubocop:disable Style/RedundantReturn
      return :skipped, "Failed to create comment: #{comment.errors.full_messages}."
    end
  end

  step :validate_user_can_interact_for_comment do
    # this step could in theory be moved higher if the user is assigned
    # to the comment sooner in the workflow
    comment.user_can_interact

    fail_on_comment_errors
  end

  step :persist_comment do
    # associating the comment to the persisted thread
    comment.pull_request_review_thread_id = thread.id
    comment.save

    if comment.errors.any?
      fail_on_comment_errors
    else
      self.pull_request_review_comment_id = comment.id
    end
  end

  step :instrument_creation_for_comment do
    comment.instrument_creation

    fail_on_comment_errors
  end

  step :subscribe_and_notify_for_comment do
    return if comment.importing?

    comment.subscribe_and_notify

    fail_on_comment_errors
  end

  step :trigger_platform_subscriptions_for_comment do
    comment.public_trigger_platform_subscriptions

    fail_on_comment_errors
  end

  step :subscribe_to_issue_for_comment do
    comment.subscribe_to_issue

    fail_on_comment_errors
  end

  # Touching a pull request is needed to kick off indexing the pull request for
  # search. This should in theory be the last hook called on the pull request
  # review comment model. We explicitly return and refrain from touching the
  # pull request model in the event that the comment isn't a legacy comment since
  # we do not need to re-index when the comment is pending or associated to a
  # pending review.
  step :touch_pull_request_after_commit_for_comment do
    return unless comment.legacy_comment?

    pull_request!.touch
  end

  # ------------------------------------------------------------
  #### Thread instrumentation and position recalculation
  # ------------------------------------------------------------

  step :ensure_thread_synced_with_pull do
    unless thread.on_file? || (thread.importing? && thread.diff_hunk.present? && thread.position.present? && thread.outdated)
      outdated = T.let(false, T::Boolean)
      position_was = thread.position
      attempt = 1
      # TODO: Any reason we can't use params.pull_request?
      pr_head_sha = PullRequest.where(id: pull_request_id, repository_id:).pick(:head_sha)

      transaction do
        while pr_head_sha != thread.commit_id
          thread.async_reposition_from_blob_position.sync
          outdated = true if position_was.present? && thread.position.nil?
          thread.save_positions(skip_blob_fields: true)

          # TODO: Any reason we can't use params.pull_request?
          # TODO: We should comment as to why we have this behavior as it smells like a source of deadlocks and killed
          # queries.
          #
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
            break # rubocop:disable Rails/TransactionExitStatement -- this exits the loop, not the transaction
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
            raise PullRequestReviewThread::PositionSyncError.new(
              "Failed to ensure new review comment position is in sync with PR"
            )
          end
        end
      end

      GitHub.dogstats.increment("pull_request.sync.position_outdated", tags: ["blob_position:false"]) if outdated
    end

    # explicitly failing for thread errors in the event that the orchestration
    # has reached this step and the thread and comment have already been
    # persisted
    fail_on_thread_errors
  end

  step :ensure_file_part_of_diff_for_thread do
    if thread.on_file?
      transaction do
        PullRequest.connection.select_rows(Arel.sql(<<-SQL, pull_request_id: pull_request_id))
          SELECT * FROM pull_requests WHERE id = :pull_request_id LOCK IN SHARE MODE
        SQL

        diff_summary = head_repository.rpc.native_read_diff_toc_with_base(
          merge_base,
          pull_request!.head_sha,
          pull_request!.base_sha
        )

        now_outdated = thread.file_level_thread_outdated_as_of_diff?(summary: diff_summary)

        thread.update(outdated: now_outdated, commit_id: pull_request!.head_sha)
      end
    end

    # explicitly failing for thread errors in the event that the orchestration
    # has reached this step and the thread and comment have already been
    # persisted
    fail_on_thread_errors
  end

  step :instrument_creation_for_thread do
    # TODO: Is this still necessary?
    unless thread.has_positioning_data?
      e = PullRequestReviewThread::PositionlessReviewThreadCreated.new
      e.set_backtrace(caller)
      Failbot.report(e, "gh.pull_request_review_thread.id": thread.id)
      GitHub.dogstats.increment("pull_request_review_threads.created_without_positioning")
    end

    thread.instrument(:create)

    GlobalInstrumenter.instrument("pull_request_review_thread.create", {
      pull_request_review_thread: thread,
      repository: repository,
    })
  end

  # ------------------------------------------------------------
  #### Review state transition
  # ------------------------------------------------------------

  step :set_skip_callbacks_for_review do
    review.skip_review_callbacks = true
  end

  step :validate_body_and_comments_for_review do
    if submit_review && review.no_body_and_no_comments?
      review.errors.add(:comment_and_body, PullRequestReview::NEEDS_COMMENTS_WHEN_REQUESTING_CHANGES)
    end

    fail_on_review_errors
  end

  step :comment_review do
    if submit_review
      review.submitted_at = Time.zone.now
      review.comment!
    end
  end

  step :submit_review_for_review do
    return unless submit_review

    GitHub.dogstats.time("pull_request_review.after_submission") do
      return false unless valid?

      pending_comments = review.review_comments.with_pending_state
      GitHub::PrefillAssociations.prefill_associations(pending_comments, :pull_request, available_records: [pull_request!])
      GitHub::PrefillAssociations.prefill_associations(pending_comments, [:user, :pull_request_review_thread, :repository])
      pending_comments.each(&:submit!)
    end
  end

  step :fulfill_review do
    return unless submit_review
    return unless review.satisfies_request?

    fullfilled_team_requests = pull_request!.team_requests_on_behalf_of(review.user)

    return unless fullfilled_team_requests.any? || pull_request!.review_requested_for?(review.user)

    pending_requests = pull_request!.review_requests_for(review.user)
    pending_or_fulfilled_requests = [fullfilled_team_requests, pending_requests].compact.reduce([], :|)
    review.review_requests = pending_or_fulfilled_requests
    ReviewRequest.where(id: pending_or_fulfilled_requests.map(&:id)).update_all(deferred: false)
  end

  step :update_pull_request_counters_for_review do
    pull_request!.update_review_and_comment_counts
  end

  step :after_commit_review do
    return unless submit_review

    event_guid = Events::Tier1EventPublisher.new_guid(Time.now)
    payload = {
      id: review.id,
      state: review.reload.state,
      issue_id: issue.id,
      actor: review.user,
      pull_request_author: pull_request!.user,
      new_reviewer_was_added: review.new_reviewer_added?,
      event_guid: event_guid,
    }

    review.instrument(:submit, payload)
    event_flags = Events::Tier1EventPublisher.calculate_event_flags(
      event_type: :pull_request_review,
      event_action: :submitted,
      target_repository_id: T.must(review.repository).id,
      target_organization_id: T.must(review.repository).organization_id
    )
    GlobalInstrumenter.instrument("pull_request_review.submit", review: review, importing: review.importing?, flags: event_flags.instrumentation_flags)
    Events::PullRequestReviewPublisher.submitted(review, event_flags: event_flags, event_guid: event_guid)

    submitted_comments = review.review_comments.with_submitted_state
    GitHub::PrefillAssociations.prefill_associations(submitted_comments, :pull_request, available_records: [pull_request!])
    submitted_comments.each { |review_comment| review_comment.allowed = review.allowed? }
    submitted_comments.each(&:instrument_submission)

    review.subscribe_and_notify unless review.importing?
    pull_request!.notify_socket_subscribers
    pull_request!.synchronize_search_index

    if review.state_previously_changed? && review.current_state > :commented
      review.notify_state_changed
      review.trigger_review_decision_updated
    end
  end

  sig { returns(T::Boolean) }
  def skip_pull_request_id_validation = true

  sig { returns(T::Boolean) }
  def skip_pull_request_review_comment_id_validation = true

  private

  sig { returns(StepTuple) }
  def skip_for_thread_validation_failure
    if thread.errors.any?
      # When skipping an orchestration, no error is raised and adding errors to
      # the base orchestration class doesn't persist them across the object boundary
      # since the orchestration record is saved. Therefore adding errors to the
      # base orchestration clas doesn't cause them to be present when manipulating
      # the object in another class. The message passed as the second argument of
      # the explicitly returned tuple from the step, however, is persisted in the
      # error_message column on the orchestration record itself

      # rubocop:disable Style/RedundantReturn
      return :skipped, "Failed to create comment: #{thread.errors.full_messages}."
    end
  end

  sig { returns(StepTuple) }
  def fail_on_thread_errors
    if thread.errors.any?
      errors.add(:base, "Thread errors: #{thread.errors.full_messages}.")
      # rubocop:disable Style/RedundantReturn
      return :failed, "Failed to create comment: #{thread.errors.full_messages}."
    end
  end

  sig { returns(StepTuple) }
  def fail_on_comment_errors
    if comment.errors.any?
      errors.add(:base, "Comment errors: #{comment.errors.full_messages}.")
      comment.instrument(:validation_failed)
      # rubocop:disable Style/RedundantReturn
      return :failed, "Failed to create comment: #{comment.errors.full_messages}."
    end
  end

  sig { returns(StepTuple) }
  def fail_on_review_errors
    if review.errors.any?
      errors.add(:base, "Review errors: #{review.errors.full_messages}.")
      # rubocop:disable Style/RedundantReturn
      return :failed, "Failed to create comment: #{review.errors.full_messages}."
    end
  end

  # ------------------------------------------------------------
  # Orchestration validations that skip
  # ------------------------------------------------------------

  sig { void }
  def validate_merge_base
    return if errors.present?

    if merge_base.blank?
      errors.add(:base, "Unable to compute merge base for pull request with id: #{pull_request!.id}")
    end
  end

  sig { void }
  def validate_pull_request_head_repository
    return if errors.present?

    if pull_request!.head_repository.nil?
      errors.add(:base, "No head repository for pull request with id: #{pull_request!.id}")
    end
  end

  sig { void }
  def validate_pull_request_lock
    return if errors.present?

    if pull_request!.issue&.locked? && !pull_request!.repository&.pushable_by?(actor)
      errors.add(:base, "Failed to create comment: Lock prevents comment")
    end
  end

  sig { void }
  def validate_review_is_pending
    return if errors.present?

    unless review.pending?
      errors.add(:base, "Failed to create comment: Pull request review must be pending")
    end
  end
end
