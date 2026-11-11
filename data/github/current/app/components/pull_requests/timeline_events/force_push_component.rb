# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class ForcePushComponent < ApplicationComponent
    include PullRequestsHelper
    include HydroHelper

    attr_reader :issue_events, :pull_request, :repository

    def initialize(issue_events:, pull_request:)
      @issue_events = issue_events
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    memoize def latest_issue_event
      issue_events.last
    end

    memoize def count
      issue_events.count
    end

    def comparison_path
      "/#{repository.owner_display_login}/#{repository.name}/compare/#{before_commit_oid}..#{after_commit_oid}"
    end

    memoize def branch
      latest_issue_event.ref_name
    end

    memoize def before_commit_oid
      latest_issue_event.before_commit_oid
    end

    memoize def after_commit_oid
      latest_issue_event.after_commit_oid
    end

    def hydro_attributes
      hydro_payload = {
        pull_request_id: pull_request.id,
        repository_id: repository.id,
        event_id: latest_issue_event.id,
      }

      hydro_click_tracking_attributes("force_push_timeline_diff.click", hydro_payload)
    end
  end
end
