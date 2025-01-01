# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# RepositoryDependencyManifestChangedJob does three things:
#   1. Pushes stats about manifest file changes.
#   2. Updates the persisted manifest files for the repository.
#   3. Updates the dependency graph API with changed manifests.
class RepositoryDependencyManifestChangedJob < ApplicationJob
  queue_as :repository_dependencies

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Faraday::ConnectionFailed, attempts: 10, wait: :polynomially_longer
  retry_on DependencyGraph::Client::ApiError, wait: :polynomially_longer
  retry_on SpokesAPI::ResourceExhausted, wait: :polynomially_longer

  JOB_RUN_LIMIT = 4.minutes

  # Since we operate on a single repository at a time, we resolve the tenant that way.
  # The arguments to the block are the arguments passed to the job.
  resolve_tenant_context do |_push_id, repository_id|
    Repositories::Public.resolve_tenant(id: repository_id)
  end

  def perform(push_id, repository_id, options = {})
    options = options.with_indifferent_access

    push = Repositories.domain.pushes.by_id_and_repo_id(repository_id: repository_id, id: push_id)

    return unless push
    return unless push.repository.present?
    return unless push.on_default_branch?

    repository = T.cast(push.repository, Repository) # rubocop:disable GitHub/AvoidCast

    return if T.must(repository.owner).spammy?
    return unless repository.dependency_graph_enabled?

    begin
      has_manifests = repository.has_manifests?(only_static_manifests: true)
    rescue DependencyGraph::BaseTwirpClient::Error => error
      GitHub.logger.error("Error calling Dependency Graph has_manifests?", {
        "code.function" => "DependenciesDependency.has_manifests?",
        "exception.message" => error.message,
        "exception.type" => error.class.name,
        "gh.repo.id" => repository.id,
        "gh.repo.push.id" => push.id,
      })

      # If we can't determine whether the repository has manifests, don't run the initialization job
      has_manifests = nil
    end

    # NOTE: This call site deliberately uses the legacy `RepositoryDependencyManifestInitializationJob`
    #
    # This safety catch is DG-API specific, we shouldn't tether DG-API's manifest change eventing to DGP as it
    # uses it's own github.dependencygraph.v1.RepositoryPush topic to directly emit pushes for DG-enabled repos.
    if push.initial_commit? || has_manifests == false
      # If this is the initial commit, or if the repository doesn't have any
      # manifests on the dg-api side, we want to initialize it.
      RepositoryDependencyManifestInitializationJob.perform_later(repository.id)
      return
    end

    changed_manifests = T.let([], T::Array[T.untyped])
    removed_manifests = T.let([], T::Array[T.untyped])

    push.spokes_api_fail_fast_enabled = true

    begin
      # Everything in the timeout-able block is readonly
      GitHub::Timer.timeout(JOB_RUN_LIMIT) do
        changed_files = push.changed_files(decompose_renames: true)
        return unless changed_files&.any?
        changed_manifests, removed_manifests = manifest_enumerator.scan_push(push)
        return unless changed_manifests.any? || removed_manifests.any?
      end
    rescue Timeout::Error => e
      # timeout, log push and repository information, then end job run
      GitHub.logger.error("Timeout pushing manifest file changes", {
        "git.commit.oid" => push.id,
        "gh.repo.id" =>  repository.id,
        :exception => e
      })
      GitHub.dogstats.increment("dependency_graph.manifest_changed.timeout")
      return
    end

    removed_files = removed_manifests.map(&:full_path)

    DependencyManifestFile.record_repository_manifest_changed_stats(
      repository: repository,
      paths: (changed_manifests.map(&:full_path) | removed_files),
    )

    event_count = (changed_manifests.count) + (removed_manifests.count)
    publisher = DependencyGraph.select_publisher(event_count)
    update_dependency_manifests(repository, removed_manifests, changed_manifests, push, publisher)

    Dependabot.repository_manifests_changed(repository: repository, reason: :on_push, push_id: push_id)
  end

  # publishes github.dependencygraph.v1.RepositoryManifestFileChange in Hydro
  def update_dependency_manifests(repository, removed_manifests, changed_manifests, push, publisher)
    changed_manifests.each do |manifest|
      payload = {
        repository_id: repository.id,
        owner_id: repository.owner_id,
        repository_private: repository.private?,
        repository_fork: repository.fork?,
        repository_nwo: repository.name_with_owner,
        repository_stargazer_count: repository.stargazer_count,
        manifest_file: {
          filename: manifest.filename,
          path: manifest.path,
          git_ref: push.after,
          pushed_at: push.created_at.to_i,
          blob_oid: manifest.blob_oid,
        },
        publisher: publisher, # metadata; removed before publish to Hydro
      }

      GlobalInstrumenter.instrument("update_manifest.repository", payload)
    end

    # Push messages for each deleted manifest file. publishes
    # github.dependencygraph.v0.RepositoryManifestFileDeleted in Hydro.
    removed_manifests.each do |manifest|
      payload = {
        repository_id: repository.id,
        repository_private: repository.private?,
        repository_fork: repository.fork?,
        repository_nwo: repository.name_with_owner,
        owner_id: repository.owner_id,
        manifest_file: {
          filename: manifest.filename,
          path: manifest.path,
          git_ref: push.after,
          pushed_at: push.created_at.to_i,
        },
        publisher: publisher, # metadata; removed before publish to Hydro
      }

      GlobalInstrumenter.instrument("delete_manifest.repository", payload)
    end
  end

  def manifest_enumerator
    @manifest_enumerator ||= ManifestEnumerator.new
  end
end
