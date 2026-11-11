# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills repository_id and organization_id columns on custom_copilot_resources
# for resources that have repository_id in their metadata JSON.
#
# This transition complements the before_save callback in CopilotSpace that populates
# these columns for new/updated resources. This backfills existing resources that were
# created before the denormalized columns were added.
module GitHub
  module Transitions
    class BackfillCopilotSpaceResourceDenormalizedRepositoryIdOrganizationId < Base
      iterate_over :database_table, params: {
        model_class: CopilotSpaceResource,
        # Only process resources that have repository_id in metadata but haven't been backfilled yet
        conditions: "denormalized_repository_id IS NULL AND JSON_EXTRACT(metadata, '$.repository_id') IS NOT NULL",
        columns: %i[id metadata],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        # Extract repository IDs from metadata
        repo_ids = items.values.filter_map do |item|
          metadata = item[:metadata]
          metadata&.dig("repository_id")
        end
        repo_ids.uniq!

        return if repo_ids.empty?

        # Batch load all repositories with their owners in a single query
        repos_by_id = Repository.where(id: repo_ids).includes(:owner).index_by(&:id)
        log("Loaded #{repos_by_id.size} repositories for batch of #{items.size} resources")

        # Build updates hash: { resource_id => { repository_id: X, organization_id: Y } }
        updates = {}

        items.each do |resource_id, item|
          metadata = item[:metadata]
          repo_id = metadata&.dig("repository_id")
          next unless repo_id

          repo = repos_by_id[repo_id]
          unless repo
            log("Warning: Repository #{repo_id} not found for resource #{resource_id}")
            next
          end

          updates[resource_id] = {
            denormalized_repository_id: repo_id,
            organization_id: repo.owner&.organization? ? repo.owner_id : nil
          }
        end

        return if updates.empty?

        if dry_run?
          log("DRY RUN: Would update #{updates.size} resources")
          updates.each do |resource_id, values|
            log("  Resource #{resource_id}: denormalized_repository_id=#{values[:denormalized_repository_id]}, organization_id=#{values[:organization_id]}")
          end
        else
          write_to(model_class: CopilotSpaceResource) do
            # Group resources by their target values to minimize database queries
            grouped_updates = updates.group_by do |_resource_id, values|
              [values[:denormalized_repository_id], values[:organization_id]]
            end

            # Batch update each group
            grouped_updates.each do |(denorm_repo_id, org_id), resource_updates|
              resource_ids = resource_updates.map { |resource_id, _| resource_id }

              CopilotSpaceResource.where(id: resource_ids).update_all(
                denormalized_repository_id: denorm_repo_id,
                organization_id: org_id
              )
            end
            log("Updated #{updates.size} resources")
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillCopilotSpaceResourceDenormalizedRepositoryIdOrganizationId.new(args).run
end
