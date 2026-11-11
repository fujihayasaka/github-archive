# typed: strict
# frozen_string_literal: true

class IssueMentionEvent < ApplicationRecord::Domain::IssuesPullRequests
  include Repositories::BelongsToRepository

  SUBJECT_TYPES = %w[Issue IssueComment PullRequestReviewComment PullRequestReview].freeze

  enum :event_type, { mention: 0, team_mention: 1 }

  belongs_to_repository_via_domain
  belongs_to :issue
  belongs_to :mentioned_user, class_name: "User", foreign_key: :mentionee_id, optional: true, inverse_of: false
  belongs_to :mentioned_team, class_name: "Team", foreign_key: :mentionee_id, optional: true, inverse_of: false
  belongs_to :subject, polymorphic: true

  scope :for_issue, ->(issue) { where(issue_id: issue.id, repository_id: issue.repository_id) }
  scope :for_mentionee, ->(mentionee_id) { where(mentionee_id: mentionee_id) }
  scope :user_mentions, -> { mention }
  scope :team_mentions, -> { team_mention }

  validates :event_type, presence: true
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }

  sig { returns(T.nilable(T.any(Team, User))) }
  def mentionee
    mention? ? mentioned_user : mentioned_team
  end
end
