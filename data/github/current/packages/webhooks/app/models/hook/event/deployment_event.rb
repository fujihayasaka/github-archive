# typed: true
# frozen_string_literal: true

class Hook::Event::DeploymentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Repository was deployed or a deployment was deleted."

  event_attr :deployment_id, required: true
  event_attr :action, required: false
  event_attr :specific_app_id

  def deployment
    @deployment ||= Deployment.find(deployment_id)
  end

  def target_repository
    deployment.repository
  end

  def actor
    deployment.creator
  end

  def check_suite
    deployment.check_run&.check_suite
  end

  def workflow_run
    check_suite&.workflow_run
  end

  def workflow
    workflow_run&.workflow
  end

end
