# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class DeploymentEnvironmentChangedComponent < ApplicationComponent

    attr_reader :issue_event, :current_user

    def initialize(issue_event:, current_user:)
      @issue_event = issue_event
      @current_user = current_user
    end

    memoize def deployment_status
      issue_event.deployment_status
    end

    memoize def environment
      deployment_status.environment
    end

    def resource_path
      issue_event.async_path_uri.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    memoize def via_app
      issue_event.async_integration_for_user(current_user).sync
    end
  end
end
