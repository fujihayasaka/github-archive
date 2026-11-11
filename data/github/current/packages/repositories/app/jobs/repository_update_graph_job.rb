# typed: true
# frozen_string_literal: true

class RepositoryUpdateGraphJob < ApplicationJob
  queue_as :graphs

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1

  locked_by key: ->(job) { job.class.lock(*job.arguments) }, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  def perform(repo_id, graph_name, skipmc = false)
    GitHub.logger.info(
      "RepositoryUpdateGraphJob started",
      "code.namespace": "RepositoryUpdateGraphJob",
      "code.function": "perform",
      "gh.repo.id": repo_id,
      "gh.repo.graph_name": graph_name,
      "skipmc": skipmc,
    )
    GitHub.cache.skip = true if skipmc
    repo = T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    if repo
      Failbot.push("gh.repo.id": repo.id)
      GitHub::RepoGraph.update(repo, graph_name)
    end
  rescue ::GitRPC::RepositoryOffline,   # fs is down, no need to be noisy
         ::GitRPC::InvalidRepository,   # repo isn't routed, probably deleted
         GitHub::DGit::UnroutedError, # again, repo isn't routed (e.g. https://git.io/fLjeL)
         ::BERTRPC::ProxyError => e          # hmm good question
    GitHub.logger.info(
      "RepositoryUpdateGraphJob exception",
      "code.namespace": "RepositoryUpdateGraphJob",
      "code.function": "perform",
      "gh.repo.id": repo_id,
      "gh.repo.graph_name": graph_name,
      "skipmc": skipmc,
      "gh.job.result": "rescued",
      "gh.error.class": e.class.name,
      exception: e,
    )
  end

  # Set the lock key to use only the network_id and not the graph name.
  # Otherwise we end up building the same graph cache up to five times if
  # all graph types are requested, or, if we use repo_id, we end up building
  # the same graph for the same network.
  def self.lock(repo_id, graph_name, skipmc = false)
    repo = Repositories.domain.by_id(repo_id)
    return unless repo  # repo was deleted
    repo.network_id.to_s
  end
end
