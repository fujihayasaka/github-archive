# typed: true
# frozen_string_literal: true

class DiscussionPollVote < ApplicationRecord::Domain::Discussions
  belongs_to :user, required: true
  # rubocop:todo Rails/InverseOf
  belongs_to :poll, class_name: "DiscussionPoll", foreign_key: :discussion_poll_id, required: true,
    counter_cache: true
  belongs_to :option, class_name: "DiscussionPollOption", foreign_key: :discussion_poll_option_id,
    required: true, counter_cache: true
  # rubocop:enable Rails/InverseOf

  validates :user, uniqueness: { scope: :poll, message: "has already voted on this poll" }, on: :create
  validate :ensure_discussion_not_locked

  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_deletion_event, on: :destroy


  private

  def ensure_discussion_not_locked
    return unless poll&.discussion&.locked?
    errors.add(:poll, "cannot be voted in because the discussion is locked")
  end

  def instrument_creation_event
    GlobalInstrumenter.instrument "discussion_poll_vote.create", discussion_poll: poll, actor: user
  end

  def instrument_deletion_event
    GlobalInstrumenter.instrument "discussion_poll_vote.delete", discussion_poll: poll, actor: user
  end
end
