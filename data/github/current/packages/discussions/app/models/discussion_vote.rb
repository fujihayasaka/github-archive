# typed: true
# frozen_string_literal: true

class DiscussionVote < ApplicationRecord::Domain::Discussions
  extend T::Sig
  include GitHub::RateLimitedCreation

  belongs_to :discussion, required: true
  belongs_to :user, required: true

  validates :discussion, uniqueness: { scope: :user, message: "has already received a vote from this user" }
  validate :user_can_vote?, on: [:create, :update]

  after_commit :sync_vote_counts, on: [:create, :update, :destroy]
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_deletion_event, on: :destroy
  after_commit :count_daily_contributors, on: [:create, :destroy]

  before_destroy :user_can_vote?

  scope :for_user, ->(user) { where(user_id: user) }
  scope :for_discussion, ->(discussion) { where(discussion_id: discussion) }

  delegate :repository, to: :discussion, allow_nil: true

  # Public: Can the given actor undo this vote?
  sig { params(actor: T.untyped).returns(T.untyped) }
  def deletable_by?(actor)
    actor == user
  end

  sig { params(discussion_id: T.untyped).returns(T.untyped) }
  def self.update_votes_counts(discussion_id)
    query = <<-SQL
      UPDATE
        discussions
      SET
        total_upvotes = (
          SELECT
            COUNT(*)
          FROM
            discussion_votes
          WHERE
            discussion_votes.discussion_id = discussions.id AND
            discussion_votes.upvote
        )
      WHERE
        discussions.id = :id
    SQL
    affected_rows = ApplicationRecord::Domain::Discussions.connection.update(Arel.sql(query, id: discussion_id))
    Search.add_to_search_index("discussion", discussion_id) if affected_rows == 1
  end

  private

  sig { void }
  def user_can_vote?
    discussion = self.discussion
    return unless user && discussion

    unless discussion.async_upvotable_by?(user).sync
      errors.add(:user, "can't vote at this time")
      throw :abort
    end
  end

  def sync_vote_counts
    return unless discussion
    DiscussionVote.update_votes_counts(discussion_id)
  end

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_vote.create", {
      actor: user,
      discussion: discussion,
      repository: repository,
      upvote: upvote,
    }
    GlobalInstrumenter.instrument "discussions_vote", {
      repository_id: repository.id,
      repository: repository,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: user&.id,
      actor: user,
      action: :VOTE_ADDED,
      action_timestamp: self.created_at
    }
  end

  sig { void }
  def instrument_deletion_event
    discussion = self.discussion

    # If there isn't a discussion, it means that this
    # deletion came as a side-effect of deleting the discussion.
    # We probably don't want to capture this in hydro as it
    # isn't an explicit user delete action.
    return unless discussion

    GlobalInstrumenter.instrument "discussion_vote.destroy", {
      actor: user,
      discussion: discussion,
      repository: repository,
      upvote: upvote,
    }

    GlobalInstrumenter.instrument "discussions_vote", {
      repository_id: repository&.id,
      repository: repository,
      discussion_id: discussion.id,
      discussion: discussion,
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
