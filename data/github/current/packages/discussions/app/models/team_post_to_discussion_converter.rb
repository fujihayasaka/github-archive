# typed: true
# frozen_string_literal: true

# Public: Used to convert a single DiscussionPost object to a Discussion.
# team_post in this code refers to a DiscussionPost object to avoid confusion with the discussion object
class TeamPostToDiscussionConverter
  extend T::Sig

  sig { returns(DiscussionPost) }
  attr_reader :team_post

  sig { returns(User) }
  attr_reader :actor

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(T.nilable(Discussion)) }
  attr_reader :discussion

  sig { returns(DiscussionCategory) }
  attr_reader :category

  BATCH_SIZE = 1000

  # Public: Create a new converter for the given team post.
  #
  # team post - the DiscussionPost to delete and replace with a discussion
  # actor - the User who initiated the conversion
  # repository - the Repository that discussions will be created on
  sig { params(team_post: DiscussionPost, actor: User, repository: Repository).void }
  def initialize(team_post, actor:, repository:)
    @team_post = team_post
    @actor = actor
    @repository = repository
    @discussion = nil
  end

  # Public: Determine if the conversion can continue. Checks to see if the conversion
  # has already started and creates the Discussion while the Team Post still exists.
  #
  # Returns a Boolean indicating if the Discussion was successfully created or already exists.
  sig { returns(T::Boolean) }
  def prepare_for_conversion
    log event: "preparing_for_converting_team_post_to_discussion"

    if (existing_discussion = team_post.discussion)
      @discussion = existing_discussion
      log event: "team_post_already_converted_to_discussion"
      return true
    end

    return false unless team_post.can_be_transferred_to_discussion?(actor, @repository)

    begin
      @category = @repository.team_post_category!
    rescue ActiveRecord::RecordInvalid
      return false # category doesn't exist and is unable to be created
    end

    # Create a discussion record to start the conversion process.
    @discussion = Discussion.from_team_discussion(team_post, repository: @repository, category: @category)

    # Set the actor to allow the converter to create a discussion in an category that requires higher permissions
    # than what the original team post author may have. See https://github.com/github/discussions/issues/1800.
    @discussion.actor = actor

    success = @discussion.save
    log event: "prepare_team_post_to_discussion_conversion_finished", success: success

    unless success && team_post.update(discussion: @discussion)
      team_post.update(discussion: nil)
      log event: "prepare_team_post_to_discussion_conversion_failed", success: false
      return false
    end
    true
  end

  # Public: Complete the conversion by copying over all the dependent records from the Team Post to
  # the Discussion
  #
  # Returns a Boolean indicating if the conversion was successful.
  sig { returns(T::Boolean) }
  def finish_conversion
    GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
      do_finish_conversion
    end
  end

  private

  sig { returns(T::Boolean) }
  def do_finish_conversion
    GitHub.dogstats.increment "team_post_to_discussion_conversion.finish.attempt"
    log event: "attempting_finish_team_post_to_discussion_conversion"

    @discussion ||= team_post.discussion

    if @discussion.nil?
      return false
    end

    success = T.let(false, T::Boolean)

    Discussion.throttle do
      Discussion.transaction do
        begin
          copy_reactions_to_discussion!
          copy_subscriptions_to_discussion!
          copy_edits_to_discussion!
          discussion_comment_id_by_reply_id = copy_comments_to_discussion!
          copy_reactions_to_discussion_comments!(discussion_comment_id_by_reply_id)
          copy_edits_to_discussion_comments!(discussion_comment_id_by_reply_id)

          @discussion.converted_at = Time.now.utc
          @discussion.state = :open

          log event: "preparing_to_save_discussion"
          @discussion.save!
          log event: "discussion_saved"

          log event: "supposedly_finished_team_post_to_discussion_conversion"
          TeamPostToDiscussionConversionVerifier.call(team_post: team_post, discussion: @discussion)
          success = true
        rescue ActiveRecord::RecordInvalid,
               ActiveRecord::Rollback,
               TeamPostToDiscussionConversionVerifier::MissingCommentsError => ex
          Failbot.report(ex)
          log event: "failed_to_finish_converting_team_post_to_discussion", error_message: ex.message
          raise ActiveRecord::Rollback, ex.message
        end
      end
    end

    if success
      GitHub.dogstats.increment "team_post_to_discussion_conversion.finish.success"
      log event: "successfully_finished_converting_team_post_to_discussion"
    end

    log event: "result_of_team_post_to_discussion_conversion", success: success

    success
  ensure
    clean_up_after_failed_conversion unless success
  end

  sig { void }
  def clean_up_after_failed_conversion
    discussion = self.discussion
    return false unless discussion.present?

    GitHub.dogstats.increment "team_post_to_discussion_conversion.finish.failure"
    log event: "clean_up_after_failed_team_post_to_discussion_conversion_started"

    if throttle_discussions { discussion.destroy }
    else
      throttle_discussions do
        discussion.update!(error_reason: :reset_conversion_failure, state: :error)
      end
    end
  end

  sig { void }
  def copy_edits_to_discussion!
    discussion = T.must_because(self.discussion) { "This method is unreachable if discussion is nil" }
    team_post.user_content_edits.each do |edit|
      attrs = user_content_edit_attributes_to_copy(edit)
      discussion.user_content_edits.create!(attrs)
    end
  end

  sig { params(discussion_comment_id_by_reply_id: T::Hash[T.untyped, T.untyped]).void }
  def copy_edits_to_discussion_comments!(discussion_comment_id_by_reply_id)
    team_post.replies.select(:id).includes(:user_content_edits).find_each(batch_size: BATCH_SIZE) do |reply|
      discussion_comment_id = discussion_comment_id_by_reply_id[reply.id]
      reply.user_content_edits.order(:id).each do |edit|
        attrs = user_content_edit_attributes_to_copy(edit)
        attrs[:discussion_comment_id] = discussion_comment_id
        DiscussionCommentEdit.create!(attrs)
      end
    end
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def copy_comments_to_discussion!
    discussion_comment_id_by_reply_id = {}
    discussion = T.must_because(self.discussion) { "This method is unreachable if discussion is nil" }

    team_post.replies.find_each(batch_size: BATCH_SIZE) do |reply|
      attrs = discussion_post_reply_attributes_to_copy(reply)
      discussion_comment = discussion.comments.create!(attrs)
      discussion_comment_id_by_reply_id[reply.id] = discussion_comment.id
    end
    discussion_comment_id_by_reply_id
  end

  sig { void }
  def copy_reactions_to_discussion!
    discussion = T.must_because(self.discussion) { "This method is unreachable if discussion is nil" }
    team_post.reactions.each do |reaction|
      attrs = reaction_attributes_to_copy(reaction)
      discussion.reactions.create!(attrs)
    end
  end

  sig { params(discussion_comment_id_by_reply_id: T::Hash[T.untyped, T.untyped]).void }
  def copy_reactions_to_discussion_comments!(discussion_comment_id_by_reply_id)
    team_post.replies.select(:id).includes(:reactions).find_each(batch_size: BATCH_SIZE) do |reply|
      discussion_comment_id = discussion_comment_id_by_reply_id[reply.id]
      reply.reactions.each do |reaction|
        attrs = reaction_attributes_to_copy(reaction)
        attrs[:discussion_comment_id] = discussion_comment_id
        DiscussionCommentReaction.create!(attrs)
      end
    end
  end

  sig { params(user_content_edit: UserContentEdit).returns(T::Hash[T.any(String, Symbol), T.untyped]) }
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

  sig { params(discussion_post_reply: DiscussionPostReply).returns(T::Hash[String, T.untyped]) }
  def discussion_post_reply_attributes_to_copy(discussion_post_reply)
    discussion_post_reply.attributes.slice(
      "created_at",
      "updated_at",
      "body",
      "formatter",
      "user_id",
    )
  end

  sig { params(reaction: Reaction).returns(T::Hash[Symbol, T.untyped]) }
  def reaction_attributes_to_copy(reaction)
    {
      content: reaction.content,
      user_id: reaction.user_id,
      created_at: reaction.created_at,
      updated_at: reaction.updated_at,
      user_hidden: reaction.user_hidden
    }
  end

  sig { void }
  def copy_subscriptions_to_discussion!
    log event: "preparing_to_copy_subscriptions_to_discussion"
    GitHub.newsies.async_copy_thread_subscribers(team_post, discussion)
  end

  sig { params(data: T::Hash[String, T.untyped]).void }
  def log(data)
    data = data.merge(
      "gh.request_id" => GitHub.context[:request_id],
      "gh.team_post.team_id" => team_post.team_id,
      "gh.team_post.id" => team_post.id,
      "gh.team_post.number" => team_post.number,
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

  sig { returns(T.any(Discussion, T::Boolean)) }
  def throttle_discussions
    Discussion.throttle do
      yield
    end
  end
end
