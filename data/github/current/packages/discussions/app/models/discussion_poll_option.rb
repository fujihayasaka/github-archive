# typed: true
# frozen_string_literal: true

class DiscussionPollOption < ApplicationRecord::Domain::Discussions
  MAX_CHAR = 128
  MIN_CHAR = 1
  # rubocop:todo Rails/InverseOf
  belongs_to :poll, class_name: "DiscussionPoll", foreign_key: :discussion_poll_id, required: true
  # rubocop:enable Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :votes, class_name: "DiscussionPollVote", foreign_key: :discussion_poll_option_id,
    dependent: :destroy
  # rubocop:enable Rails/InverseOf
  validates :option, length: { minimum: MIN_CHAR, maximum:  MAX_CHAR }
  validates :option, presence: true

  after_commit :reset_poll_votes!

  sig { returns String }
  def to_s
    option
  end

  # Public: Indicates if a user has voted for this specific option for the poll.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def has_voted?(user)
    return false unless user.present?
    votes.where(user: user).exists?
  end

  private

  sig { returns T.nilable(T::Boolean) }
  def reset_poll_votes!
    poll&.reset_votes!
  end
end
