# typed: true
# frozen_string_literal: true

class Hook::Event::DeploymentStatusEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Deployment status updated from the API."

  event_attr :deployment_status_id, required: true
  event_attr :action, required: false

  def deployment_status
    @deployment_status ||= DeploymentStatus.find(deployment_status_id)
  end

  def target_repository
    deployment_status.repository
  end

  def actor
    deployment_status.creator
  end

  def deployment
    deployment_status.deployment
  end

  def check_run
    deployment&.check_run
  end

  def check_suite
    check_run&.check_suite
  end

  def workflow_run
    check_suite&.workflow_run
  end

  def workflow
    workflow_run&.workflow
  end

end
