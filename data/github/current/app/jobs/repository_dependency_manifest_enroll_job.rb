# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This should be used when a Repository is enabling Dependency Graph to tell all downstream services to backfill data
# from source files.
#
# This should be considered a replacement for RepositoryDependencyManifestInitializationJob in enablement code paths,
# for cases where the manifest data needs to be refreshed rather than backfilled, use RepositoryDependencyRedetectJob
#
# For Dependency Graph activation logic, see:
# - packages/security_products/app/models/security_product/dependency_graph.rb
class RepositoryDependencyManifestEnrollJob < ApplicationJob
  queue_as :repository_dependencies
  retry_on_dirty_exit

  def perform(repository_id, actor_id: nil)
    repository = Repositories.domain.by_id(repository_id)
    return false if repository.nil?

    actor = if actor_id
      User.find_by(id: actor_id)
    end

    DependencyGraphPlatform.publish_manifest_enroll_event(
      repository: repository,
      actor: actor || User.ghost,
    )

    enqueue_legacy_enroll(repository)

    true
  end

  private

  def enqueue_legacy_enroll(repository)
    RepositoryDependencyManifestInitializationJob.perform_later(repository.id)
  end
end
