# typed: true
# frozen_string_literal: true

class DiscussionPoll < ApplicationRecord::Domain::Discussions
  belongs_to :discussion, required: true

  has_many :options, class_name: "DiscussionPollOption", dependent: :destroy, inverse_of: :poll
  accepts_nested_attributes_for :options, allow_destroy: true, reject_if: :all_blank

  has_many :votes, class_name: "DiscussionPollVote", dependent: :destroy

  MIN_OPTIONS = 2
  MAX_OPTIONS = 8
  MAX_QUESTION_LENGTH = 255

  attr_accessor :actor

  validates :question, length: { maximum: MAX_QUESTION_LENGTH }, presence: true
  validates :options, length: { minimum: MIN_OPTIONS, maximum: MAX_OPTIONS }

  before_validation :purge_blank_options
  after_update_commit :reset_votes!, if: :question_previously_changed?
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update, if: -> do
    T.bind(self, DiscussionPoll)
    previous_changes.present?
  end
  after_destroy_commit :instrument_deletion_event

  # Public: Indicates if a user has voted for any option for this poll.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def has_voted?(user)
    return false unless user.present?
    votes.where(user: user).exists?
  end

  # Public: Reset all of the votes for this discussion.
  sig { returns T::Boolean }
  def reset_votes!
    return true unless votes.exists?

    # Delete all votes directly with SQL. No callbacks are run.
    DiscussionPollVote.where(discussion_poll_id: id).delete_all

    # Since we called `delete_all` on the poll's votes to avoid extra queries,
    # we need to reset the counters manually. This is a raw SQL upate, and done
    # without any callbacks for performance reasons.
    DiscussionPoll.connection.update(Arel.sql(<<-SQL, discussion_poll_id: id))
      UPDATE discussion_polls
      SET discussion_poll_votes_count = 0
      WHERE id = :discussion_poll_id
    SQL

    DiscussionPollOption.connection.update(Arel.sql(<<-SQL, discussion_poll_id: id))
      UPDATE discussion_poll_options
      SET discussion_poll_votes_count = 0
      WHERE discussion_poll_id = :discussion_poll_id
    SQL

    true
  end

  sig { returns String }
  def to_s
    option_strings = options.map { |poll_option| "- #{poll_option}" }
    text = <<~MARKDOWN
      #{question}

      #{option_strings.join("\n")}
    MARKDOWN
    text.strip
  end

  private

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_poll.create", discussion_poll: self

    message = {
      repository_id: discussion&.repository_id,
      repository: discussion&.repository,
      repository_owner: discussion&.repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: actor&.id,
      actor: actor,
      action: :ACTION_POLL_CREATED,
      action_timestamp: created_at,
      poll_id: id,
    }
    GlobalInstrumenter.instrument "discussions_poll", message
  end

  sig { void }
  def instrument_deletion_event
    GlobalInstrumenter.instrument "discussion_poll.delete", discussion_poll: self, actor: actor

    message = {
      repository_id: discussion&.repository_id,
      repository: discussion&.repository,
      repository_owner: discussion&.repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: actor&.id,
      actor: actor,
      action: :ACTION_POLL_DELETED,
      action_timestamp: Time.now,
      poll_id: id,
    }
    GlobalInstrumenter.instrument "discussions_poll", message
  end

  sig { void }
  def instrument_update_event
    GlobalInstrumenter.instrument "discussion_poll.update", discussion_poll: self, actor: actor

    message = {
      repository_id: discussion&.repository_id,
      repository: discussion&.repository,
      repository_owner: discussion&.repository&.owner,
      discussion_id: discussion&.id,
      discussion: discussion,
      actor_id: actor&.id,
      actor: actor,
      action: :ACTION_POLL_UPDATED,
      action_timestamp: updated_at,
      poll_id: id,
    }
    GlobalInstrumenter.instrument "discussions_poll", message
  end

  sig { void }
  def purge_blank_options
    persisted_options = options.select(&:persisted?)
    persisted_options.each do |option|
      option.mark_for_destruction if option.option.blank?
    end
  end
end
