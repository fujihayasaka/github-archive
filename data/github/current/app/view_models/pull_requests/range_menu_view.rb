# typed: true
# frozen_string_literal: true

module PullRequests
  class RangeMenuView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :pull_comparison

    def pull
      @pull ||= pull_comparison.pull
    end

    def most_recent_review
      return unless current_user
      @most_recent_review ||= pull.latest_non_pending_review_for(current_user)
    end

    def reviewed?
      most_recent_review.present?
    end

    def reviewed_current_diff?
      most_recent_review&.applies_to_current_diff?
    end

    def changes_since_last_reviewed_range
      pull.changes_since_last_review_diff_range(current_user)
    end

    def no_changes_since_last_review_description
      "No new changes"
    end
  end
end
