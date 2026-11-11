# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  # Event describing one or more pull request reviews that were dismissed.
  class ReviewDismissedComponent < ApplicationComponent
    def initialize(issue_events:, pull_request:)
      @issue_events = issue_events
      @pull_request = pull_request
    end

    memoize def actor
      first_event.event_actor(viewer: current_user)
    end

    # A component describing the action that was taken including the
    # authors of the dismissed review or reviews.
    def description_component
      if single_event?
        PullRequests::TimelineEvents::ReviewDismissed::SingleDescriptionComponent.new(
          issue_event: first_event, actor: actor, pull_request: @pull_request
        )
      else
        PullRequests::TimelineEvents::ReviewDismissed::MultipleDescriptionComponent.new(
          issue_events: @issue_events, actor: actor, pull_request: @pull_request
        )
      end
    end

    # Note: this and the other commit_ methods do things differently
    # than the graphql loader to avoid a gitrpc call and just use the commit
    # oid from the db as-is.
    memoize def commit_oid
      first_event.after_commit_oid
    end

    def commit_path
      if commit_oid
        repo = first_event.repository
        "/#{repo.owner_display_login}/#{repo}/commit/#{commit_oid}"
      end
    end

    def abbreviated_commit_oid
      if commit_oid
        commit_oid[0, Commit::ABBREVIATED_OID_LENGTH]
      end
    end

    memoize def dismissal_message_html
      first_event.dismissal_message
    end

    private

    def single_event?
      @issue_events.size == 1
    end

    memoize def first_event
      @issue_events.first
    end
  end
end
