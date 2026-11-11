# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::DeploymentEnvironmentChangedEventAdapter < Issue::Adapter::IssueEventAdapter
  DEPLOYMENT_ENVIRONMENT_CHANGED_EVENT = "DeploymentEnvironmentChangedEvent"

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: DEPLOYMENT_ENVIRONMENT_CHANGED_EVENT)
    @pull_request = context.pull_request
  end
end
