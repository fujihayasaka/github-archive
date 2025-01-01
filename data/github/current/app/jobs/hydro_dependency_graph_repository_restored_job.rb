# typed: true
# frozen_string_literal: true

class HydroDependencyGraphRepositoryRestoredJob < Repositories::RepositoryHydroMessageJob
  include Repositories::Domain::Provider

  queue_as :hydro_dependency_graph_repository_restored

  retry_on_dirty_exit

  # Public: process the github.repositories.v2.Restored Hydro event, triggering
  #         downstream Dependency Graph repo restoration, if eligible.
  #
  # Returns nothing
  def perform
    raise_error("failed to resolve Repository model for given repo ID") unless repository
    unless repository.dependency_graph_enabled?
      GitHub.logger.info(
        message: "skipping restored repository: Dependency Graph disabled for repository",
        repository_id: repository.id)
      GitHub.dogstats.increment("dependency_graph.repository_restored", tags: ["result:skipped", "scope:repo"])
      return
    end

    push = repositories_domain.pushes.latest_by_after_and_ref(repository_id: repository.id, ref: "refs/heads/#{repository.default_branch}")

    push_id = push&.id
    raise_error("failed to resolve latest push ID for default branch: #{repository.default_branch}") unless push_id

    GitHub.logger.info(
      message: "reindexing Dependency Graph for restored repository",
      repository_id: repository.id)
    GitHub.dogstats.increment("dependency_graph.repository_restored", tags: ["result:processed", "scope:repo"])

    RepositoryDependencyManifestInitializationJob.perform_later(repository.id, { push_id: push_id })
  end

  class Error < ::StandardError; end

  def raise_error(msg)
    GitHub.logger.error("gh.dg.hydro_message_job.error": msg)
    GitHub.dogstats.increment("dependency_graph.repository_restored.error")

    raise Error.new(msg)
  end

  protected

  # Additional logging context for raised errors, to allow for event introspection in Hydro app
  # https://github.com/github/github/blob/master/packages/repositories/app/public/repositories/repository_hydro_message_job.rb#L26-L32
  def logging_context
    super.merge({
      "gh.dg.hydro_message_job.name": self.class.to_s,
      "messaging.kafka.source.topic": topic,
      "messaging.kafka.source.partition": partition,
      "messaging.kafka.source.offset": offset,
    })
  end
end
