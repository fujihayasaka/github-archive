# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroDependencyGraphRepositoryRestoredJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_dependency_graph_repository_restored

  retry_on_dirty_exit

  # Public: process the github.repositories.v2.Restored Hydro event, triggering
  #         downstream Dependency Graph repo restoration, if eligible.
  #
  # Returns nothing
  def perform
    unless repository.dependency_graph_enabled?
      GitHub.logger.info(
        message: "skipping restored repository: Dependency Graph disabled for repository",
        repository_id: repository.id)
      GitHub.dogstats.increment("dependency_graph.repository_restored", tags: ["result:skipped", "scope:repo"])
      return
    end

    GitHub.logger.info(
      message: "reindexing Dependency Graph for restored repository",
      repository_id: repository.id)
    GitHub.dogstats.increment("dependency_graph.repository_restored", tags: ["result:processed", "scope:repo"])

    RepositoryDependencyRedetectJob.perform_later(repository.id, trigger: :RESET_TRIGGER_REPO_RESTORED)
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
