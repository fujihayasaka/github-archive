# typed: true
# frozen_string_literal: true

class RepositoryUpdateLanguageStatsJob < ApplicationJob
  queue_as :languages
  retry_on_dirty_exit

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ApplicationJob::DEFAULT_TIMEOUT

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id)
    repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repo_id)
    end
    if repository
      Failbot.push("gh.repo.id": repo_id)
      with_write { repository.analyze_languages }
    end
  rescue GitRPC::Protocol::DGit::ResponseError => e
    GitHub.logger.error(
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.id" => repo_id
    )

    # In rare cases the language stats differ on the replicas.
    # Let's remove all stats in this case as they are calculated
    # incrementally and we want to ensure failures do not propagate.
    if repository && e.message =~ /backends disagreed/i
      with_write { repository.clear_languages }
    end

    nil
  end
end
