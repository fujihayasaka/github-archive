# frozen_string_literal: true

module HandleWebhook
  class WorkflowRun
    # GHES alone uses this webhook.
    # TODO Replace this webhook by ComputeUsage hydro event (GitHubActionComputeUsageHandler)
    # once the ComputeUsage hydro event is published in GHES.
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      return unless dependabot_update_action?

      Dependabot::Logger.info(
        msg: "Dependabot workflow_run webhook received",
        "code.namespace": "HandleWebhook::WorkflowRun",
        "gh.actions.workflow_run.id": workflow_run_id,
        "gh.repo.id": github_repo_id,
        "gh.actions.workflow_run.status": workflow_run_status,
        "gh.actions.workflow_run.conclusion": workflow_run_conclusion,
      )

      return unless workflow_has_failed?

      HandleFailedActionRunJob.perform_later(workflow_run_id: workflow_run_id)
    end

    private

    def workflow_run_id
      webhook_body[:workflow_run][:id]
    end

    def github_repo_id
      webhook_body[:repository][:id]
    end

    def workflow_run_status
      webhook_body[:workflow_run][:status]
    end

    def workflow_run_conclusion
      webhook_body[:workflow_run][:conclusion]
    end

    # This guards against us reacting to any out of band retries via Actions APIs we haven't locked down
    def dependabot_update_action?
      webhook_body[:sender][:login] == "dependabot[bot]" &&
        webhook_body[:workflow_run][:event] == "dynamic"
    end

    def workflow_has_failed?
      workflow_run_status == GitHub::CheckRun::Status::COMPLETED &&
        workflow_run_conclusion != GitHub::CheckRun::Conclusion::SUCCESS
    end
  end
end
