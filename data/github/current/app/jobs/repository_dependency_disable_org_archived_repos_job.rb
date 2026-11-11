# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job disables dependency graph on each archived repository in an organization.
# It is enqueued by the .dependency_graph disable_for_org_archived_repos chatop.
class RepositoryDependencyDisableOrgArchivedReposJob < ApplicationJob
  queue_as :repository_dependencies
  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(org, actor)
    archived_repos = org.repositories.archived_scope
    org_name = "(id: #{org.id}, name: #{org.name})"

    Rails.logger.info("Disabling dependency graph on archived repositories for org: #{org_name}")

    total_repos_disabled = 0

    archived_repos.in_batches(of: BATCH_SIZE) do |batch|
      dg_enabled_repos = batch.select(&:dependency_graph_enabled?)
      dg_enabled_repos.each do |repo|
        with_write { repo.disable_dependency_graph(actor: actor) }
      end
      total_repos_disabled += dg_enabled_repos.size
    end

    Rails.logger.info("Disabled dependency graph on #{total_repos_disabled} archived repositories under org: #{org_name}")
  end
end
