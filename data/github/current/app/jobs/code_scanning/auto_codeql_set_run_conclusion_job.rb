# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CodeScanning::AutoCodeqlSetRunConclusionJob < ApplicationJob
  queue_as :code_scanning

  before_perform do |job|
    Failbot.push(job: job.class.name)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on CodeScanning::AutoCodeqlError, attempts: 5, wait: :polynomially_longer

  def perform(repository_id:, workflow_run_id:)
    repository = Repositories::Public.find_active(repository_id)
    return unless repository
    repository = T.must_because(repository) { "if repository was nil we would have returned early in the preceding line" }

    Failbot.push(
      repository_id: repository_id,
      workflow_run_id: workflow_run_id,
    )

    workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(id: workflow_run_id)
    if workflow_run.nil?
      GitHub.logger.info("Workflow run not found, skipping set_run_conclusion",
        "gh.actions.workflow_run.id" => workflow_run_id,
        "gh.repo.id" => repository_id,
      )
      return
    end

    if workflow_run.workflow_file_path != CodeScanning::AutoCodeql::WORKFLOW_FILE_PATH
      GitHub.logger.info("Workflow run is not a code scanning workflow, skipping set_run_conclusion",
        "gh.actions.workflow_run.id" => workflow_run.id,
        "gh.repo.id" => repository_id,
        "gh.workflow_run.path" => workflow_run.workflow_file_path,
      )
      return
    end

    if workflow_run.check_suite.nil?
      GitHub.logger.info("Workflow run check suite is not set, skipping set_run_conclusion",
        "gh.actions.workflow_run.id" => workflow_run.id,
        "gh.repo.id" => repository_id,
      )
      return
    end

    if !workflow_run.completed?
      GitHub.logger.info("Workflow run is not completed, skipping set_run_conclusion",
        "gh.actions.workflow_run.id" => workflow_run.id,
        "gh.repo.id" => repository_id,
      )
      return
    end

    CodeScanning::AutoCodeql.new(repository).set_completed_run_conclusion(run: workflow_run)
  end
end
