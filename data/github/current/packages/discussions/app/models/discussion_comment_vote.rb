# typed: true
# frozen_string_literal: true

class DiscussionCommentVote < ApplicationRecord::Domain::Discussions
  include GitHub::RateLimitedCreation

  belongs_to :discussion, required: true
  belongs_to :comment, class_name: "DiscussionComment", foreign_key: "comment_id" # rubocop:todo Rails/InverseOf
  belongs_to :user, required: true

  validates :comment, uniqueness: { scope: [:user, :discussion], message: "has already received a vote from this user" }
  validate :comment_matches_discussion
  validate :user_can_vote?, on: [:create, :update]

  after_commit :sync_vote_counts, on: [:create, :update, :destroy]
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_deletion_event, on: :destroy

  before_destroy :user_can_vote?

  # Community Insights data
  after_commit :count_daily_contributors, on: [:create, :destroy]

  scope :for_user, ->(user) { where(user_id: user) }
  scope :for_comment, ->(comment) { where(comment_id: comment) }
  scope :for_discussion, ->(discussion) { where(discussion_id: discussion) }

  delegate :repository, to: :discussion, allow_nil: true

  TOTAL_VOTE_SYNC_INTERVAL = 3.seconds.to_i
  UPDATE_INTERVAL = 10.seconds.to_i

  # Public: Can the given actor undo this vote?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def deletable_by?(actor)
    actor == user
  end

  sig { params(comment_id: T.untyped).returns(T.untyped) }
  def self.update_votes_counts(comment_id)
    query = <<-SQL
      UPDATE
        discussion_comments
      SET
        total_upvotes = (
          SELECT
            COUNT(*)
          FROM
            discussion_comment_votes
          WHERE
            discussion_comment_votes.comment_id = discussion_comments.id AND
            discussion_comment_votes.upvote
        )
      WHERE
        discussion_comments.id = :id
    SQL
    ApplicationRecord::Domain::Discussions.connection.update(Arel.sql(query, id: comment_id))
  end

  private

  sig { void }
  def comment_matches_discussion
    comment = self.comment
    return unless comment && discussion_id

    unless comment.discussion_id == discussion_id
      errors.add(:comment, "is not for the same discussion")
    end
  end

  sig { void }
  def user_can_vote?
    comment = self.comment
    return unless user && comment

    unless comment.async_upvotable_by?(user).sync
      errors.add(:user, "can't vote at this time")
      throw :abort
    end
  end

  sig { returns T::Boolean }
  def can_interact?
    return @_can_interact if defined?(@_can_interact)
    @_can_interact = User::InteractionAbility.interaction_allowed?(user: user, repository: repository)
  end

  sig { void }
  def sync_vote_counts
    return unless comment
    DiscussionCommentVote.update_votes_counts(comment_id)
  end

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_comment_vote.create", {
      actor: user,
      comment: comment,
      discussion: discussion,
      repository: repository,
      upvote: upvote,
    }

    GlobalInstrumenter.instrument "discussions_comment_vote", {
      repository_id: repository.id,
      repository: repository,
      repository_owner: repository.owner,
      discussion_comment_id: comment&.id,
      actor_id: user&.id,
      actor: user,
      action: :VOTE_ADDED,
      action_timestamp: Time.now
    }
  end

  sig { void }
  def instrument_deletion_event
    # If there isn't a comment, it means that this
    # deletion came as a side-effect of deleting the comment.
    # We probably don't want to capture this in hydro as it
    # isn't an explicit user delete action.
    comment = self.comment
    return unless comment

    GlobalInstrumenter.instrument "discussion_comment_vote.destroy", {
      actor: user,
      comment: comment,
      discussion: discussion,
      repository: repository,
      upvote: upvote,
    }

    GlobalInstrumenter.instrument "discussions_comment_vote", {
      repository_id: repository&.id,
      repository: repository,
      repository_owner: repository&.owner,
      discussion_comment_id: comment.id,
      actor_id: user&.id,
      actor: user,
      action: :VOTE_REMOVED,
      action_timestamp: Time.now
    }
  end

  sig { void }
  def count_daily_contributors
    return unless repository.present?
    created_at = self.created_at || Time.current
    CommunityInsights::DiscussionsDailyContributorsJob.perform_later(repository.id, created_at.to_date)
  end
end
