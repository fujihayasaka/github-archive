# typed: true
# frozen_string_literal: true

class Discussions::BatchVotesController < Discussions::BaseController
  before_action :require_xhr
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    keyed_responses = ActiveRecord::Base.connected_to(role: :reading) do
      item_batch.map_inputs do |handler|
        handler&.discussion do |discussion|
          if discussion
            render_to_string Discussions::VoteFormComponent.new(
              subject: discussion,
              vote: votes_by_discussion_id[discussion.id],
              voting_enabled: voting_enablement[:discussions][discussion.id],
            ), layout: false
          end
        end

        handler&.comment do |comment|
          if comment
            render_to_string Discussions::VoteFormComponent.new(
              subject: comment,
              vote: votes_by_comment_id[comment.id],
              voting_enabled: voting_enablement[:comments][comment.id],
            ), layout: false
          end
        end
      end
    rescue ActionController::ParameterMissing
      return head :bad_request
    end

    respond_to do |format|
      format.json do
        render json: keyed_responses
      end
    end
  end

  private

  memoize def item_batch
    Discussion::CommentItemBatch.new(current_repository, params)
  end

  # Load any DiscussionCommentVotes created by the current user.
  #
  # Returns a Hash mapping integer comment ID to the loaded DiscussionCommentVote instances.
  memoize def votes_by_comment_id
    DiscussionCommentVote
      .where(comment: item_batch.comment_ids, user: current_user)
      .index_by(&:comment_id)
  end

  # Load any DiscussionVotes created by the current user.
  #
  # Returns a Hash mapping integer discussion ID to the loaded DiscussionVote instances.
  memoize def votes_by_discussion_id
    DiscussionVote
      .where(discussion: item_batch.discussion_ids, user: current_user)
      .index_by(&:discussion_id)
  end

  # Determine which records within the requested batch - Discussions and DiscussionComments - the current user has
  # permission to upvote.
  #
  # Returns a Hash mapping ":discussion" to the Discussion votability result and each comment ID to its votability
  # result.
  memoize def voting_enablement
    promises = []
    result = { comments: {}, discussions: {} }

    item_batch.discussions.each do |discussion|
      promises << discussion.async_upvotable_by?(
        current_user,
        interaction_allowed: can_interact_with_repo?,
      ).then do |is_upvotable|
        result[:discussions][discussion.id] = is_upvotable
      end
    end

    item_batch.comments.each do |comment|
      promises << comment.async_upvotable_by?(
        current_user,
        interaction_allowed: can_interact_with_repo?,
      ).then do |is_upvotable|
        result[:comments][comment.id] = is_upvotable
      end
    end

    # Because of the .then blocks above, resolving these Promises will populate the `result` Hash.
    Promise.all(promises).sync
    result
  end
end
