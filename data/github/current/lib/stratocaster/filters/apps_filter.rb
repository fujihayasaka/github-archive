# typed: true
# frozen_string_literal: true
#
module Stratocaster::Filters
  class AppsFilter < BaseFilter

    def self.appropriate_issues_or_pull_requests_permission
      proc do |event, viewer|
        if event.pull_request_url.present?
          viewer.installation.permissions.key?("pull_requests")
        else
          viewer.installation.permissions.key?("issues")
        end
      end
    end

    def self.blocked
      proc { false }
    end

    def self.check_permission(subject_type)
      proc do |_event, viewer|
        viewer.installation.permissions.key?(subject_type)
      end
    end

    EVENT_PERMISSION_REQUIREMENTS = {
      Stratocaster::Event::COMMIT_COMMENT_EVENT              => check_permission("contents"),
      Stratocaster::Event::CREATE_EVENT                      => check_permission("contents"),
      Stratocaster::Event::DELETE_EVENT                      => check_permission("contents"),
      Stratocaster::Event::FOLLOW_EVENT                      => blocked,
      Stratocaster::Event::FORK_EVENT                        => check_permission("contents"),
      Stratocaster::Event::GOLLUM_EVENT                      => check_permission("contents"),
      Stratocaster::Event::ISSUE_COMMENT_EVENT               => appropriate_issues_or_pull_requests_permission,
      Stratocaster::Event::ISSUES_EVENT                      => check_permission("issues"),
      Stratocaster::Event::MEMBER_EVENT                      => check_permission("administration"),
      Stratocaster::Event::PUBLIC_EVENT                      => check_permission("metadata"),
      Stratocaster::Event::PULL_REQUEST_EVENT                => check_permission("pull_requests"),
      Stratocaster::Event::PULL_REQUEST_REVIEW_EVENT         => check_permission("pull_requests"),
      Stratocaster::Event::PULL_REQUEST_REVIEW_COMMENT_EVENT => check_permission("pull_requests"),
      Stratocaster::Event::PUSH_EVENT                        => check_permission("contents"),
      Stratocaster::Event::RELEASE_EVENT                     => check_permission("contents"),
      Stratocaster::Event::WATCH_EVENT                       => check_permission("metadata"),
    }

    # Filters a list of events to exclude events that can't be viewed by the
    # current GitHub App, based on its fine-grained permissions.
    #
    # events - Array of Stratocaster::Event items to filter
    #
    # Returns an Array of Stratocaster::Event items
    def self.apply(events, viewer)
      events.select do |event|
        next true if event.public?

        filter = EVENT_PERMISSION_REQUIREMENTS[event.event_type]
        next false unless filter

        filter.call(event, viewer)
      end
    end
  end
end
