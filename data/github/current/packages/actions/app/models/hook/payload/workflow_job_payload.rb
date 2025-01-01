# typed: true
# frozen_string_literal: true

class Hook::Payload::WorkflowJobPayload < Hook::Payload
  def to_payload_hash
    payload = {
      action: hook_event.action,
      workflow_job: api_serialize(:job_hash, { job: hook_event.workflow_job.check_run }),
    }

    payload.merge(deployment_hash)
  rescue NoMethodError, ActiveRecord::ActiveRecordError => e
    GitHub.logger.error("failed to serialize workflow job payload", {
      "code.namespace" => self.class.name,
      "code.function" => "to_payload_hash",
      "gh.check_run.id" => hook_event.workflow_job&.check_run_id,
      "gh.repo.id" => hook_event.workflow_job&.repository_id,
      "gh.workflow_run.id" => hook_event.workflow_job&.workflow_run_id,
      "gh.workflow_job_run.id" => hook_event.workflow_job&.id,
      "gh.webhook.action" => hook_event.attributes[:action],
      :exception => e
    })
  end

  def deployment_hash
    if hook_event.workflow_job.check_run.deployment
      { deployment: api_serialize(:deployment_hash, hook_event.workflow_job.check_run.deployment) }
    else
      {}
    end
  end
end
