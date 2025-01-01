# typed: false
# frozen_string_literal: true

class RepositoryUpdateGraphJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :graphs

  locked_by key: ->(job) { job.class.lock(*job.arguments) }, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  def perform(repo_id, graph_name, skipmc = false)
    GitHub.cache.skip = true if skipmc
    ActiveRecord::Base.connected_to(role: :reading) do
      if repo = Repository.find_by_id(repo_id)
        Failbot.push("gh.repo.id": repo.id)
        GitHub::RepoGraph.update(repo, graph_name)
      end
    end
  rescue ::GitRPC::RepositoryOffline,   # fs is down, no need to be noisy
         ::GitRPC::InvalidRepository,   # repo isn't routed, probably deleted
         GitHub::DGit::UnroutedError, # again, repo isn't routed (e.g. https://git.io/fLjeL)
         ::BERTRPC::ProxyError          # hmm good question
  end

  # Set the lock key to use only the network_id and not the graph name.
  # Otherwise we end up building the same graph cache up to five times if
  # all graph types are requested, or, if we use repo_id, we end up building
  # the same graph for the same network.
  def self.lock(repo_id, graph_name, skipmc = false)
    repo = ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by_id(repo_id) }
    return unless repo  # repo was deleted
    repo.network_id.to_s
  end
end
