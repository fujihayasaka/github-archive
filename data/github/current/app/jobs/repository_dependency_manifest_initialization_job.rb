# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# WARN: Avoid new uses of this job!
#
# This job is a legacy activation path that does not incorporate events that Dependency Graph Platform (DGP) uses
# to onboard or refresh repositories.
#
# Historically, this job has been used for both first-time onboarding of a repository and redetection/repair which we
# would prefer to distinguish for Dependency Graph Platform. If you identify a need to trigger Dependency Graph setup
# then you should use one of the following jobs that wrap this job with DGP events:
#
# - If the repository's Dependency Graph setting is going from active to inactive, use:
#     app/jobs/repository_dependency_manifest_enroll_job.rb
#
# - If the repository's Dependency Graph setting is not changing, use:
#     app/jobs/repository_dependency_redetect_job.rb
#

# Does three things:
#   1. Pushes stats about manifest file changes.
#   2. Persists manifest files for the repository.
#   3. Updates the dependency graph API with detected manifests.
class RepositoryDependencyManifestInitializationJob < ApplicationJob
  include Repositories::Domain::Provider

  queue_as :repository_dependencies

  class InvalidRepositoryError < StandardError; end

  locked_by timeout: 5.minutes, key: ->(job) { job.arguments[0] }

  retry_on_dirty_exit

  RETRYABLE_EXCEPTIONS = [
    *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS,
    *Resiliency::Response::UnavailableExceptions,
    GitHub::DGit::UnroutedError,
    GitRPC::NetworkError,
    GitHub::Spokes::ClientError
  ]
  retry_on *RETRYABLE_EXCEPTIONS, attempts: 10, wait: :polynomially_longer

  retry_on DependencyGraph::Client::TimeoutError, attempts: 3, wait: :polynomially_longer

  def perform(repository_id, options = {})
    options = options.with_indifferent_access
    scan_for_vulnerabilities = options.fetch(:scan_for_vulnerabilities, true)

    repository = Repository.find_by(id: repository_id)
    raise InvalidRepositoryError, "Repository not found" unless repository&.default_oid
    raise InvalidRepositoryError, "Repository has null oid" unless repository.default_oid != GitHub::NULL_OID
    raise InvalidRepositoryError, "Dependency graph not enabled" unless repository.dependency_graph_enabled?

    return if T.must(repository.owner).spammy?

    # Redo detection after KV update is done
    manifest_enumerator = ManifestEnumerator.new
    manifests = manifest_enumerator.scan_repository(repository, repository.default_oid)

    DependencyManifestFile.record_repository_manifest_changed_stats(
      repository: repository,
      paths: manifests.map(&:full_path),
      initial_commit: true
    )
    if options[:push_id]
      push = repositories_domain.pushes.by_id_and_repo_id(repository_id: repository_id, id: options[:push_id].to_i) if options[:push_id]
    end
    # TODO: Remove snapshotting as we never shipped the feature?
    should_snapshot = push && DependencyGraph.push_eligible_for_snapshot?(repository)

    publisher = DependencyGraph.select_publisher(manifests&.count || 0)

    # This will emit a new Hydro message of type
    # github.dependencygraph.v1.RepositoryManifestFileChange per
    # manifest. These messages will be processed in dependency-graph-api.
    manifests.each do |manifest|
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
          git_ref: repository.default_oid,
          pushed_at: repository.pushed_at.to_i,
          blob_oid: manifest.blob_oid,
        },
        publisher: publisher, # metadata; removed before publish to Hydro
      }

      if should_snapshot && manifest_eligible_for_snapshot(manifest)
        associated_manifest = T.let(nil, T.untyped)
        GitHub.dogstats.distribution_time("dependency_graph.manifest_changed.resolve_associated_manifest.dist") do
          associated_manifest = resolve_associated_manifest(repository, push, manifest, manifests)
        end
        GitHub.logger.info("Submitting enriched manifest change event", {
          "gh.repo.push.id" => push.id,
          "gh.repo.id" => repository.id,
          "gh.commit.ref" => push.ref,
          "git.commit.oid" => push.after,
        })
        GitHub.dogstats.increment("dependency_graph.manifest_changed.snapshot_event.publish", { event_type: "init" })

        payload[:snapshot_metadata] = {
          associated_manifest: associated_manifest,
          push_id: push.id,
          ref: push.ref,
          commit_sha: push.after,
        }
      end

      GlobalInstrumenter.instrument("update_manifest.repository", payload)
    end

    scan_dependencies_for_vulnerabilities(repository, manifests) if scan_for_vulnerabilities
  rescue ::GitRPC::InvalidRepository, InvalidRepositoryError => err
    # The repository either doesn't exist yet or has been deleted. Either way
    # we should behave as though we hadn't found the repository in the database.
    GitHub.logger.error("Skipping #{self.queue_name}", {
      "gh.job.queue" => self.queue_name,
      "gh.job.name" => self.class.name,
      "gh.repo.id" => repository_id,
      :exception => err
    })
    nil
  end

  private

  # If a repository has any manifest paths, we should send an event to
  # Dependabot so it can activate dependency updates and scan for
  # vulnerabilities.
  #
  # If the repository no longer has any manifest files,
  # but repository vulnerability alerts still remain,
  # Dependabot should ultimately remove those alerts.
  #
  # It's important that this method is separated and conditionally executed
  # based on the scan_for_vulnerabilities option, so we can skip it for certain repositories.
  def scan_dependencies_for_vulnerabilities(repository, manifests)
    if manifests.any? || repository.repository_vulnerability_alerts.any?
      Dependabot.repository_manifests_changed(repository: repository, reason: :on_initialize)
    end
  end

  # best-effort attempt to obtain "package.json" blob OID and metadata
  # associatd with the target "package-lock.json" to be submitted as snapshot
  def resolve_associated_manifest(repository, push, manifest, changed_manifests)
    # attempt one (cheap): obtain matching "package.json" file meta from current push
    pj_manifest = changed_manifests.find do |m|
      m.path == manifest.path &&
        m.filename.strip.downcase == "package.json"
    end

    if pj_manifest
      return {
        filename: pj_manifest.filename,
        path: pj_manifest.path,
        blob_oid: pj_manifest.blob_oid,
        git_ref: push.after.to_s, # just including for completeness, not needed!
        pushed_at: push.created_at.to_i, # same here
      }
    else
      begin
        # attempt two (expensive): obtain matching "package.json" file meta from Git
        subtree = repository.directory(push.ref, manifest.path)
        associated = subtree&.tree_entries&.find { |te| te[:name].strip.downcase == "package.json" }

        if associated
          filename = associated.display_name
          path = associated.simplified_path ? associated.simplified_utf8_path : ""

          return {
            filename: filename,
            path: path,
            blob_oid: associated.oid,
            git_ref: push.after.to_s, # just including for completeness, not needed!
            pushed_at: push.created_at.to_i, # same here
          }
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        GitHub.logger.error("Resolve associated manifest error", {
          "gh.repo.push.id" => push.id,
          "gh.repo.id" => repository.id,
          :exception => e
        })
        GitHub.dogstats.increment("dependency_graph.manifest_changed.resolve_associated_manifest.error", { type: "#{e.class.to_s.downcase}" })
      end
    end

    # best effort failed :(
    nil
  end

  def manifest_eligible_for_snapshot(manifest)
    manifest&.filename.to_s.strip.downcase == "package-lock.json"
  end
end
