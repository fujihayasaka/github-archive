# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  class GetDiscussionSkillResponse
    include GitHub::Memoizer
    include Copilot::Prompt::Tokens

    # We have about 4_000 tokens to work with but we also need to factor in the JSON keys. So we deduct some
    # tokens to account for that. We also want some buffer for followup questions.
    MAX_TOKENS = 1_500
    MAX_DISCUSSION_COMMENTS = 40
    MAX_REPLIES_PER_COMMENT = 10
    TOO_MANY_COMMENTS_MESSAGE = <<-TEXT.squish
      There are too many comments so you must let the user know the results are
      incomplete by putting this message only at the very end of the response:
      'Some of the discussion's comments could not be read because the discussion body and
      comments combined are too long.'
    TEXT
    DISCUSSION_BODY_TOO_LARGE = <<-TEXT.squish
      The discussion is too big so only part of the body was included and no comments
      are available. You must let the user know the results are incomplete by
      putting this message only at the very end of the response: 'Part of the
      discussion's body could not be read and no comments were read because the discussion
      body is too long.'
    TEXT

    sig { params(discussion: ::Discussion, current_user: ::User).void }
    def initialize(discussion:, current_user:)
      @discussion = discussion
      @current_user = current_user
      @ingested_replied_comments = 0
    end

    sig { returns T::Hash[Symbol, T::Hash[Symbol, T.untyped]] } # rubocop:disable Sorbet/ForbidTUntyped
    def payload
      {
        discussion: {
          number: discussion.number,
          title: discussion.title,
          body: discussion_body_and_comments.to_s,
          user: {
            login: discussion.user&.display_login
          },
          state: discussion.state,
          id: discussion.id,
          repo_id: discussion.repository_id,
          url: discussion.permalink,
          repo_name: discussion.repository&.name,
          repo_owner: discussion.repository.owner&.display_login,
          answer: answer,
        }
      }
    end

    private

    attr_reader :discussion, :current_user

    # Returns a Hash that will be used as a string that the model can use to get the discussion body and comments
    # The model doesn't really care that the Hash is stringified since to the model it appears in the same way.
    #
    # This makes it so that we can quickly iterate on comments until we have a better idea of how we'd like to use
    # it. For example, we may want a separate skill, or we may want to add a new field to the existing get_discussion
    # Twirp endpoint.
    #
    # See: https://github.com/github/copilot-core-productivity/issues/1529
    sig { returns(T::Hash[Symbol, T.any(String, T::Array[T::Hash[Symbol, String]])]) }
    def discussion_body_and_comments
      payload = {
        # Only get the body up until the token limit
        body: discussion.body.first(MAX_TOKENS * Copilot::Prompt::Tokens::CHARACTERS_PER_TOKEN),
        comments: discussion_comments_hash
      }

      if discussion_body_token_count > MAX_TOKENS
        # If the body is too big then no comments will be included. Let the user know
        payload.merge(ai_notes: DISCUSSION_BODY_TOO_LARGE)
      elsif discussion_comments_hash.count + @ingested_replied_comments < total_discussion_comments_count
        # If some comments were removed then let's let the user know
        payload.merge(ai_notes: TOO_MANY_COMMENTS_MESSAGE)
      else
        # Otherwise don't return any notes about truncation
        payload
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
    memoize def discussion_comments_hash
      # Start with the discussion body token count. That way if the body is huge we only add a few comments. If the body
      # is small we can add more comments.
      total_content_token_count = discussion_body_token_count
      arr = []

      discussion_parent_comments.each_with_index do |comment, index|
        v = {
          body: comment.body,
          author: comment.user&.display_login,
          created_at: comment.created_at
        }
        total_content_token_count += count_tokens(comment.body)
        # If adding this comment would put us over the limit, break out of
        # the loop and skip the rest of the comments.
        break if total_content_token_count >= MAX_TOKENS
        arr << v

        replies = discussion_comment_replies(comment)
        rep_arr = []
        replies.each do |reply|
          vv = {
            body: reply.body,
            author: reply.user&.display_login,
            created_at: reply.created_at
          }
          total_content_token_count += count_tokens(reply.body)
          # If adding this reply would put us over the limit, break out of
          # the loop and skip the rest of the replies.
          break if total_content_token_count >= MAX_TOKENS
          rep_arr << vv
          @ingested_replied_comments += 1
        end unless replies.nil?

        arr[index][:replies] = rep_arr
      end

      arr
    end

    sig { returns(Integer) }
    memoize def discussion_body_token_count
      count_tokens(discussion.body)
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) } # rubocop:disable Sorbet/ForbidTUntyped
    def answer
      return unless discussion.chosen_comment
      {
         author: discussion.chosen_comment.user.display_login,
         created_at: Google::Protobuf::Timestamp.new(seconds: discussion.chosen_comment.created_at.to_i),
         body: discussion.chosen_comment.body,
       }
    end

    sig { returns T::Array[DiscussionComment] }
    memoize def discussion_comments
      DiscussionComment
        .where(discussion: discussion)
        .includes(:user)
        # Get rid of the noise
        .where(comment_hidden: false, performed_by_integration_id: nil)
        .filter_spam_for(current_user)
        # Sort to get the oldest comments first since comments can be threaded. Then
        .sorted_by(:created_at, :asc)
        # Limit them so we don't overwhelm the database.
        .limit(MAX_DISCUSSION_COMMENTS)
        .to_a
    end

    sig { returns T::Array[DiscussionComment] }
    memoize def discussion_parent_comments
      DiscussionComment
        .where(discussion: discussion)
        .includes(:user)
        .top_level
        # Get rid of the noise
        .where(comment_hidden: false, performed_by_integration_id: nil)
        .filter_spam_for(current_user)
        # Sort to get the oldest comments first since comments can be threaded. Then
        .sorted_by(:created_at, :asc)
        # Limit them so we don't overwhelm the database.
        .limit(MAX_DISCUSSION_COMMENTS)
        .to_a
    end

    sig { returns Integer }
    memoize def total_discussion_comments_count
      DiscussionComment
        .where(discussion: discussion)
        .includes(:user)
        # Get rid of the noise
        .where(comment_hidden: false, performed_by_integration_id: nil)
        .filter_spam_for(current_user)
        # Sort to get the oldest comments first since comments can be threaded. Then
        .sorted_by(:created_at, :asc)
        .size
    end

    sig { params(comment: DiscussionComment).returns(T::Array[DiscussionComment]) }
    def discussion_comment_replies(comment)
      DiscussionComment
        .where(discussion: discussion)
        .includes(:user)
        .child_of(comment)
        # Get rid of the noise
        .where(comment_hidden: false, performed_by_integration_id: nil)
        .filter_spam_for(current_user)
        # Sort to get the oldest comments first since comments can be threaded. Then
        .sorted_by(:created_at, :asc)
        .limit(MAX_REPLIES_PER_COMMENT)
        .to_a
    end
  end
end
