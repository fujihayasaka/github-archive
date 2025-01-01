# frozen_string_literal: true

# This job deletes the given repository entry (given by github_repository_id)
# in order to clear the dependencies for that repository.
# It should be enqueued to Aqueduct in Dotcom and is pulled off the queue
# by the aqueduct-worker.
class ClearDependenciesJob < RetryJob
  BATCH_SIZE = 200

  def perform(github_repository_id)
    repository = Repository.find_by_github_repository_id(github_repository_id)

    unless repository.present?
      DependencyGraph.logger.info("Could not find Repository by github_repository_id",
        "gh.repo.id" => github_repository_id
      )
      Instrument.increment("etl.clear_dependencies_job", result: "repo_not_found")
      return
    end

    begin
      # delete batches of dependent models in reverse cascade
      DependencyGraph.logger.info("Clearing repository dependencies: manifest dependencies",
        "gh.repo.id" => github_repository_id)
      repository.manifests.in_batches(of: BATCH_SIZE) do |batch_of_manifests|
        batch_of_manifests.each do |manifest|
          ManifestDependency
            .select(:id)
            .where(manifest_id: manifest.id)
            .in_batches(of: BATCH_SIZE) do |batch_of_deps|
            batch_of_deps.destroy_all
          end

          ManifestEntry
            .select(:id)
            .where(manifest_id: manifest.id)
            .in_batches(of: BATCH_SIZE) do |batch_of_deps|
            batch_of_deps.destroy_all
          end

          manifest.destroy
        end
      end

      DependencyGraph.logger.info("Clearing repository dependencies: abstract repository dependencies",
        "gh.repo.id" => github_repository_id)
      repository.abstract_dependencies.select(:id).in_batches(of: BATCH_SIZE) do |batch_of_deps|
        batch_of_deps.destroy_all
      end

      DependencyGraph.logger.info("Clearing repository dependencies: star counts",
        "gh.repo.id" => github_repository_id)
      StarCount
        .select(:id)
        .where(github_repository_id: repository.github_repository_id)
        .destroy_all # should only be one of these per repo!

    rescue StandardException => e
      DependencyGraph.logger.error("Clearing repository dependencies: attempt failed",
                                   "exception.type" => e.class.name,
                                   "gh.repo.id" => github_repository_id)
      Instrument.increment("etl.clear_dependencies_job", result: "failed", error: e.class.name)

      raise e
    end

    DependencyGraph.logger.info("Clearing repository dependencies: completed successfully",
      "gh.repo.id" => github_repository_id)
    Instrument.increment("etl.clear_dependencies_job", result: "successful")
  end
end
