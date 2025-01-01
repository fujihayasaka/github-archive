# typed: true
# frozen_string_literal: true

module Discussions
  class VoteFormComponent < ApplicationComponent
    include UsersHelper

    VOTE_SYNC_INTERVAL = 1.minute.to_i

    delegate :repository, to: :subject

    attr_reader :subject

    def initialize(subject:, vote: nil, voting_enabled:)
      @subject = subject
      @vote = vote
      @voting_enabled = fetch_or_fallback([true, false], voting_enabled, false)
    end

    def render?
      @subject.present?
    end

    def has_voted?
      vote&.persisted?
    end

    def has_upvoted?
      has_voted? && vote.upvote?
    end

    def discussion_voting_path
      if subject_is_comment?
        discussion_comment_votes_path(repository.owner, repository, subject.discussion, subject)
      else
        discussion_votes_path(repository.owner, repository, subject)
      end
    end

    def subject_is_comment?
      subject.is_a?(DiscussionComment)
    end

    def upvoted_vote_count
      default_vote_count + 1
    end

    memoize def default_vote_count
      # In rare occasions, if the `total_upvotes` field is not up to date,
      # we need to guard against returning `-1` for the default vote count.
      # See https://github.com/github/discussions/issues/1640.
      if has_upvoted? && subject.total_upvotes.zero?
        # Enqueue job to fix out of sync `total_upvotes` field.
        CalculateDiscussionTotalVotesJob.enqueue_once_per_interval(
          args: [subject.discussion_id],
          interval: VOTE_SYNC_INTERVAL,
        )

        return 0
      end

      return subject.total_upvotes - 1 if has_upvoted?

      subject.total_upvotes
    end

    def voting_disabled?
      !@voting_enabled
    end

    def upvote_identifier
      format = aria_label_date(discussion.created_at)
      "#{discussion.author}, #{discussion.created_at.to_formatted_s(format)}"
    end

    def sparkle_votes_enabled?
      repository.sparkle_votes_enabled? && !current_user&.opted_out_of_sparkle_votes?
    end

    private

    attr_reader :vote

    def button_color
      if !has_upvoted?
        :muted
      elsif voting_disabled? && has_upvoted?
        :accent
      else
        nil
      end
    end

    def discussion
      if subject_is_comment?
        subject.discussion
      else
        subject
      end
    end

    def disabled_reason
      if logged_in? && voting_disabled?
        "You can't vote on a locked discussion"
      else
        "You must be logged in to vote"
      end
    end
  end
end
