# typed: true
# frozen_string_literal: true

# Public: Used to convert a single Issue to a Discussion.
class IssueToDiscussionConverter
  attr_reader :issue, :actor, :discussion, :category, :issue_originally_open

  # Public: Create a new converter for the given issue.
  #
  # issue - the Issue to delete and replace with a Discussion
  # actor - the User who initiated the conversion
  # issue_originally_open - an optional Boolean representing if the Issue was originally in 'open'
  #                         state, and thus should be reopened if the conversion fails; omit if
  #                         this is not known. NOTE: This arg will be deprecated in
  #                         the future, see https://github.com/github/discussions/issues/1523
  # category - an optional DiscussionCategory to categorize the Discussion once it's created. If unspecified, the
  #            fallback category of the repository will be used.
  sig do
    params(
      issue: T.untyped,
      actor: T.untyped,
      issue_originally_open: T.untyped,
      category: T.untyped
    ).void
  end
  def initialize(issue, actor:, issue_originally_open: nil, category: nil)
    @issue = issue
    @actor = actor
    @category = category || @issue.repository.fallback_discussion_category!
    @discussion = nil
    @issue_originally_open = issue_originally_open
  end

  # Public: Determine if the conversion can continue. Checks to see if the conversion
  # has already started, if the issue can be closed to start the conversion, and
  # creates the Discussion while the Issue still exists.
  #
  # Returns a Boolean indicating if the Discussion was successfully created or already
  # exists for the Issue.
  sig { returns(T::Boolean) }
  def prepare_for_conversion
    log event: "preparing_for_converting_issue_to_discussion"
    # See if this issue is already being converted to a discussion.
    if (existing_discussion = issue.discussion)
      @discussion = existing_discussion
      log event: "issue_already_converted_to_discussion"
      return true
    end

    return false unless issue.can_be_converted_by?(actor)

    # Mark if the issue was originally open in case we have to rollback
    @issue_originally_open = issue.open?

    # Create a discussion record to start the conversion process.
    @discussion = Discussion.from_issue(issue, category: @category)

    # Set the actor to allow the converter to create a discussion in an category that requires higher permissions
    # than what the original issue author may have. See https://github.com/github/discussions/issues/1800.
    @discussion.actor = actor

    # Return whether the discussion was successfully updated:
    success = @discussion.save
    log event: "prepare_issue_to_discussion_conversion_finished", success: success
    success
  end

  # Public: Complete the conversion by copying over all the dependent records from the Issue to
  # the Discussion and deleting the original Issue.
  #
  # Returns a Boolean indicating if the conversion was successful.
  sig { returns(T::Boolean) }
  def finish_conversion
    GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
      do_finish_conversion
    end
  end

  private

  def do_finish_conversion
    GitHub.dogstats.increment "issue_to_discussion_conversion.finish.attempt"
    log event: "attempting_finish_issue_to_discussion_conversion"

    @discussion ||= issue.discussion

    if @discussion.nil?
      log event: "already_finished_converting_issue_to_discussion"
      return false
    end

    success = T.let(false, T::Boolean)

    throttle_discussions do
      Discussion.transaction do
        begin
          copy_reactions_to_discussion!
          copy_labels_to_discussion!
          copy_edits_to_discussion!
          copy_comments_to_discussion!
          copy_subscriptions_to_discussion!

          if issue.locked?
            log event: "preparing_to_lock_discussion"
            lock_discussion
            log event: "finished_locking_discussion"
          end

          # Set counter caches to comment count, since we skip the callback that
          # usually does this as part of the conversion process.
          @discussion.comment_count = @discussion.comments.size
          @discussion.direct_comment_count = @discussion.comments.size

          @discussion.state = :open
          @discussion.converted_at = Time.now.utc
          log event: "preparing_to_save_discussion"
          @discussion.save!
          log event: "discussion_saved"

          issue.lock(actor)

          # Mark the issue as converted
          unless issue.mark_as_converted_to_discussion(actor: actor)
            log event: "marking_issue_as_converted_failed_for_discussion_conversion"
            raise ActiveRecord::Rollback
          end

          log event: "supposedly_finished_issue_to_discussion_conversion"
          IssueToDiscussionConversionVerifier.verify!(issue, discussion)
          success = true
        rescue ActiveRecord::RecordInvalid, ActiveRecord::Rollback => ex
          Failbot.report(ex)
          log event: "failed_to_finish_converting_issue_to_discussion", error_message: ex.message
          raise ActiveRecord::Rollback, ex.message
        end
      end
    end

    if success
      GitHub.dogstats.increment "issue_to_discussion_conversion.finish.success"
      log event: "successfully_finished_converting_issue_to_discussion"
      # TODO: create audit log entry about discussion conversion
    end

    log event: "result_of_issue_to_discussion_conversion", success: success

    success
  ensure
    clean_up_after_failed_conversion unless success
  end

  def clean_up_after_failed_conversion
    GitHub.dogstats.increment "issue_to_discussion_conversion.finish.failure"
    log event: "clean_up_after_failed_issue_to_discussion_conversion_started"

    # Prefer to delete the discussion entirely so the user's issue can continue being used:
    if throttle_discussions { discussion.destroy }
      if issue.closed? && issue_originally_open
        throttle_issues do
          issue.open(actor)
        end
      end
    else
      # If deleting the discussion fails for whatever reason, try to log that the discussion
      # isn't in a good state, either:
      throttle_discussions do
        discussion.update!(error_reason: :reset_conversion_failure, state: :error)
      end
    end
  end

  def copy_reactions_to_discussion!
    issue.reactions.each do |reaction|
      attrs = reaction_attributes_to_copy(reaction)
      discussion.reactions.create!(attrs)
    end
  end

  def copy_labels_to_discussion!
    discussion.replace_labels(issue.labels)
  end

  def copy_edits_to_discussion!
    issue.user_content_edits.each do |edit|
      attrs = user_content_edit_attributes_to_copy(edit)

      # temporary workaround for for issue_edit ignore "diff" column.
      attrs["diff"] = edit.compressed_diff unless attrs.key?("diff")

      discussion.user_content_edits.create!(attrs)
    end
  end

  def copy_comments_to_discussion!
    log event: "copying_comments_from_issue_to_discussion_started"
    issue.comments.each_with_index do |comment, index|
      # Make sure we are actually attempting to copy a comment. Just log the
      # first few comments so we don't overload the logs
      copy_comment_to_discussion!(comment, should_log: index.in?([0, 1]))
    end
    log event: "finished_copying_comments_from_issue_to_discussion"
  end

  def copy_comment_to_discussion!(issue_comment, should_log:)
    if should_log
      log event: "preparing_to_copy_comment_for_issue_to_discussion_conversion",
        issue_comment_id: issue_comment.id
    end

    discussion_comment = throttle_discussions do
      if should_log
        log event: "copying_comment_from_issue_to_discussion", issue_comment_id: issue_comment.id
      end

      discussion.comments.create!(
        user: issue_comment.safe_user,
        body: issue_comment.body,
        repository: issue.repository,
        updated_at: issue_comment.updated_at,
        created_at: issue_comment.created_at,
        formatter: issue_comment.formatter,
        comment_hidden: issue_comment.comment_hidden,
        comment_hidden_reason: issue_comment.comment_hidden_reason,
        comment_hidden_classifier: issue_comment.comment_hidden_classifier,
        comment_hidden_by: issue_comment.comment_hidden_by,
        skip_user_blocking_validation: true,
        # Skip the callback for calculating discussion count every time a comment created,
        # and instead just do it once when completing the conversion.
        # See https://github.com/github/discussions/issues/2916.
        skip_update_discussion_comment_count: true,
      )

    end

    if should_log
      log event: "supposedly_copied_comment_from_issue_to_discussion",
        issue_comment_id: issue_comment.id
    end

    copy_comment_reactions_to_discussion_comment!(issue_comment, discussion_comment: discussion_comment, should_log: should_log)
    copy_comment_edits_to_discussion_comment!(issue_comment, discussion_comment: discussion_comment, should_log: should_log)
  end

  def copy_comment_reactions_to_discussion_comment!(issue_comment, discussion_comment:, should_log:)
    if should_log
      log event: "preparing_to_copy_comment_reactions_to_discussion_comment",
        issue_comment_id: issue_comment.id,
        discussion_comment_id: discussion_comment.id
    end

    issue_comment.reactions.each do |reaction|
      attrs = reaction_attributes_to_copy(reaction)
      discussion_comment.reactions.create!(attrs)
    end

    if should_log
      log event: "finished_copying_comment_reactions_to_discussion_comment",
        issue_comment_id: issue_comment.id,
        discussion_comment_id: discussion_comment.id
    end
  end

  def copy_comment_edits_to_discussion_comment!(issue_comment, discussion_comment:, should_log:)
    if should_log
      log event: "preparing_to_copy_edits_to_discussion_comment",
        issue_comment_id: issue_comment.id,
        discussion_comment_id: discussion_comment.id
    end

    issue_comment.user_content_edits.each do |edit|
      attrs = user_content_edit_attributes_to_copy(edit)
      discussion_comment.user_content_edits.create!(attrs)
    end

    if should_log
      log event: "finished_copying_edits_to_discussion_comment",
        issue_comment_id: issue_comment.id,
        discussion_comment_id: discussion_comment.id
    end
  end

  def user_content_edit_attributes_to_copy(user_content_edit)
    user_content_edit.attributes.slice(
      "edited_at",
      "editor_id",
      "created_at",
      "updated_at",
      "performed_by_integration_id",
      "deleted_at",
      "deleted_by_id",
      "diff",
    )
  end

  def reaction_attributes_to_copy(reaction)
    {
      content: reaction.content,
      user_id: reaction.user_id,
      created_at: reaction.created_at,
      updated_at: reaction.updated_at,
      user_hidden: reaction.user_hidden
    }
  end

  def lock_discussion
    lock_event = issue.events.locks.last
    @discussion.lock(actor: lock_event.actor)
  end

  def copy_subscriptions_to_discussion!
    log event: "preparing_to_copy_subscriptions_to_discussion"
    GitHub.newsies.async_copy_thread_subscribers(issue, discussion)
  end

  def users_ignoring_issue
    @users_ignoring_issue ||= User.where(id: issue_subscriber_set.ignored).select(:id)
  end

  def issue_subscriber_set
    @subscriber_set ||= GitHub.newsies.subscriber_set_for(
      list: @issue.repository,
      thread: @issue,
    )
  end

  def throttle_discussions
    Discussion.throttle do
      yield
    end
  end

  def throttle_issues
    Issue.throttle do
      yield
    end
  end

  def log(data)
    data = data.merge(
      "gh.request_id" => GitHub.context[:request_id],
      "gh.issue.id" => issue.id,
      "gh.issue.number" => issue.number,
      "gh.issue.comments.count" => issue.issue_comments_count,
      "gh.discussion.id" => discussion&.id,
      "gh.discussion.number" => discussion&.number,
      "gh.discussion.cached_comments.count" => discussion&.comment_count,
      "gh.discussion.live_comments.count" => discussion&.comments&.count,
      "gh.discussion.converted_at" => discussion&.converted_at,
      "gh.discussion.state" => discussion&.state,
      "gh.discussion.error_reason" => discussion&.error_reason,
      "gh.discussion.reaction.count" => discussion&.reactions&.count,
      "gh.actor.id" => actor.id,
    )
    GitHub.logger.info(data)
  end
end
