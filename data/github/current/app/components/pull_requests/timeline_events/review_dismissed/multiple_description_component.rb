# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents::ReviewDismissed
  # The description of a review_dismissed event involving multiple reviews.
  class MultipleDescriptionComponent < ApplicationComponent
    include ViewComponent::InlineTemplate

    erb_template <<~'ERB'
      dismissed stale reviews from <%= review_author_list %>
    ERB

    attr_reader :issue_events, :pull_request

    def initialize(issue_events:, actor:, pull_request:)
      @issue_events = issue_events
      @actor = actor
      @pull_request = pull_request
    end

    # A linkified list of review authors whose review was dismissed.
    def review_author_list
      subjects = reviews_by_others.uniq.map do |review|
        render PullRequests::TimelineEvents::UserLinkComponent.new(user: review&.user)
      end
      subjects << "themself" if reviews_by_event_actor.any?
      html_safe_to_sentence(subjects)
    end

    private

    def reviews_by_event_actor
      grouped_reviews[0]
    end

    def reviews_by_others
      grouped_reviews[1]
    end

    # Reviews partitioned by whether they were dismissed by the event actor.
    memoize def grouped_reviews
      reviews.partition do |review|
        review&.user&.display_login == @actor&.display_login
      end
    end

    memoize def reviews
      review_ids = issue_events.map(&:pull_request_review_id)
      reviews_by_id = pull_request.reviews_for(current_user).select { |review| review_ids.include?(review.id) }.index_by(&:id)
      # preserve order and also nils for missing records
      review_ids.map { |id| reviews_by_id[id] }
    end
  end
end
