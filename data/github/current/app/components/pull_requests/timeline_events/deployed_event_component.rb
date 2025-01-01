# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class DeployedEventComponent < ApplicationComponent

    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
    end

    # would be nice to remove this someday but we'll need to run a transition to remove all deployment events that have missing deployments.
    def render?
      deployment.present?
    end

    memoize def deployment
      issue_event.deployment
    end

    memoize def status
      deployment.latest_status
    end

    memoize def description
      deployment_description_text(deployment.state)
    end

    def show_env_url
      status && !%w[inactive destroyed].include?(deployment.state) &&
        status.environment_url.present?
    end

    def resource_path
      issue_event.async_path_uri.sync
    end

    memoize def via_app
      issue_event.async_integration_for_user(current_user).sync
    end

    def websocket_channel
      GitHub::WebSocket::Channels.pull_request(pull_request)
    end

    def live_update_url
      pull_request_deployed_event_partial_path(id: pull_request.number, event_id: issue_event.id)
    end

    def deployment_description_text(state)
      case state
      when "pending", "waiting", "abandoned", "in_progress", "queued"
        "requested a deployment"
      when "active"
        "deployed"
      when "inactive", "destroyed"
        "temporarily deployed"
      when "failure", "error", nil
        "had a problem deploying"
      end
    end

    def final_deployment_state?
      %w[abandoned destroyed error failure inactive].include?(deployment.state)
    end
  end
end
