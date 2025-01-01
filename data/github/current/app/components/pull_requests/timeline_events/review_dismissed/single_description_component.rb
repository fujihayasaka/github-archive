# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents::ReviewDismissed
  # The description of a review_dismissed event involving a single review.
  class SingleDescriptionComponent < ApplicationComponent
    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, actor:, pull_request:)
      @issue_event = issue_event
      @actor = actor
      @pull_request = pull_request
    end

    memoize def review
      return nil unless issue_event.pull_request_review_id

      pull_request.reviews_for(current_user).find { |review| review.id == issue_event.pull_request_review_id }
    end

    def review_link
      if review
        render(Primer::Beta::Link.new(href: "##{review.anchor}", scheme: :secondary)) { "stale review" }
      end
    end

    def reviewer_link
      return unless review
      return "their" if self_dismissed?
      render PullRequests::TimelineEvents::UserLinkComponent.new(user: review.user)
    end

    def self_dismissed?
      review&.user&.display_login == @actor&.display_login
    end
  end
end
