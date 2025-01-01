# typed: true
# frozen_string_literal: true

class ReachabilityAnalysisJob < ApplicationJob
  include Reachability::ActionsWorkflow
  extend T::Sig

  queue_as :reachability

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0] }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  class InvalidActorError < StandardError; end

  sig { params(repo_id: T.any(Integer, String), actor: T.nilable(String)).void }
  def perform(repo_id, actor:)
    workflow_run_exists = false
    workflow_id, sha = nil # so ensure block is safe when failures occur

    user = User.find_by_login(actor)
    raise InvalidActorError if user.nil?

    repo = Repositories::Public.find_active!(repo_id)
    sha = repo.default_oid

    # Using the `actions` integration for demo, will replace with our own
    workflow_id = create_workflow_run(actor: user, repo: repo, sha: sha, job_id: job_id)
    workflow_run_exists = true if workflow_id
  ensure
    GitHub.logger.info(
      "Reachability workflow triggered", {
        "actor": actor,
        "repo.id": repo_id,
        "sha": sha,
        "success": workflow_run_exists,
        "workflow.id": workflow_id,
      }
    )
  end
end
