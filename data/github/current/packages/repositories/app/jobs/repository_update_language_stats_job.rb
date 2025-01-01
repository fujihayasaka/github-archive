# typed: false
# frozen_string_literal: true

class RepositoryUpdateLanguageStatsJob < ApplicationJob
  default_to_write_connection! # rubocop:disable GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :languages

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ApplicationJob::DEFAULT_TIMEOUT

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id)
    if repository = Repository.find_by_id(repo_id)
      Failbot.push("gh.repo.id": repo_id)
      repository.analyze_languages
    end
  rescue GitRPC::Protocol::DGit::ResponseError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repo_id
    )

    nil
  end
end
