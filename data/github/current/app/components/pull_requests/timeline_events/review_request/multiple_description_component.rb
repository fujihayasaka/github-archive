# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents::ReviewRequest
  # The description of a group of events of type
  # `review_requested` or `review_request_removed`.
  class MultipleDescriptionComponent < ApplicationComponent
    attr_reader :issue_events, :pull_request

    def initialize(issue_events:, pull_request:)
      @issue_events = issue_events
      @pull_request = pull_request
      @requested_reviewers = {}
      @requested_review_team_names = {}
      @requested_review_assigned_from_team_names = {}
    end

    memoize def requested_events
      partitioned_events[0]
    end

    memoize def request_removed_events
      partitioned_events[1]
    end

    memoize def first_review_request
      requested_events.first&.review_request
    end

    def codeowner_link
      href = first_review_request&.async_codeowners_path_uri&.sync
      if href.present?
        render(Primer::Beta::Link.new(href: href, scheme: :secondary)) { "code owners" }
      end
    end

    # The User or Team record that the event requests review from, if the
    # current viewer can see them.
    # Note: this and requested_review_team_name are a giant source of N+1s,
    # assuming that in real usage their promises will be preloaded.
    def requested_reviewer(event)
      return @requested_reviewers[event] if @requested_reviewers.key?(event)
      @requested_reviewers[event] = event.visible_subject_for(current_user)
    end

    def missing_reviewer_name(event)
      event.subject_type == "Team" ? "a team" : "a user"
    end

    # If a team review request, the name of the team whose review was requested.
    # Ported from ReviewRequestedEvent#requested_review_team_name
    def requested_review_team_name(event)
      return @requested_review_team_names[event] if @requested_review_team_names.key?(event)
      @requested_review_team_names[event] = begin
        reviewer = requested_reviewer(event)
        if reviewer.is_a?(Team)
          reviewer.async_organization.then do |org|
            "#{T.must(org).name}/#{reviewer.slug}"
          end.sync
        end
      end
    end

    # If this event is for a review request delegated from a team, return the
    # name of the team whose review request it was delegated from.
    def requested_review_assigned_from_team_name(event)
      return @requested_review_assigned_from_team_names[event] if @requested_review_assigned_from_team_names.key?(event)
      @requested_review_assigned_from_team_names[event] = event.review_request&.prelude_visible_assigned_from_team_name(current_user) if event.event == "review_requested"
    end

    private

    def partitioned_events
      requested, request_removed = issue_events.partition { |e| e.event == "review_requested" }
      requested.uniq! { |event| requested_reviewer(event) }
      request_removed.uniq! { |event| requested_reviewer(event) }
      [requested, request_removed]
    end
  end
end
