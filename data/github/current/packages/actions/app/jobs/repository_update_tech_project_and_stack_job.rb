# typed: true
# frozen_string_literal: true

class RepositoryUpdateTechProjectAndStackJob < ApplicationJob
  queue_as :tech_project_stack
  retry_on_dirty_exit
  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ApplicationJob::DEFAULT_TIMEOUT

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id)
    if repository = with_read do
      Repositories.domain.by_id(repo_id)
    end
      Failbot.push(repo_id: repo_id)
      TechProjectStackAnalysis.analyze_tech_project_stacks(repository)
    end
  end
end
