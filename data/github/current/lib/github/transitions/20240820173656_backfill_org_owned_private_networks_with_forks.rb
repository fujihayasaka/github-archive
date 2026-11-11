# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillOrgOwnedPrivateNetworksWithForks < Base
      class Repositories < ApplicationRecord::Domain::Repositories
        self.table_name = "repositories"
      end

      class OrgOwnedPrivateNetworkWithForks < ApplicationRecord::Domain::Repositories
        self.table_name = "org_owned_private_networks_with_forks"
      end

      iterate_over :database_table, params: {
        model_class: Repositories,
        columns: [:source_id, :owner_id],
        conditions: "organization_id IS NOT NULL AND public = 0 AND parent_id IS NULL AND"\
         " (SELECT COUNT(*) from repositories as fork WHERE fork.source_id = repositories.source_id"\
         " AND fork.parent_id IS NOT NULL LIMIT 1) > 0",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        rows = items.map { |item| item[1].merge({ root_id: item[0] }) }

        if dry_run?
          log "Would have inserted OrgOwnedPrivateNetworkWithForks for networks with root_id, network_id, owner_id: #{rows.map { |row| "#{row[:root_id]}, #{row[:source_id]}, #{row[:owner_id]}" }}" if verbose?
          return
        end

        rows.each do |row|
          if OrgOwnedPrivateNetworkWithForks.exists?(network_id: row[:source_id])
            write_to(model_class: OrgOwnedPrivateNetworkWithForks) do
              OrgOwnedPrivateNetworkWithForks
                .where(network_id: row[:source_id])
                .update_all(
                  {
                    owner_id: row[:owner_id],
                    updated_at: Time.now
                  }
                )
            end
          else
            write_to(model_class: OrgOwnedPrivateNetworkWithForks) do
              OrgOwnedPrivateNetworkWithForks
                .insert(
                  {
                    network_id: row[:source_id],
                    owner_id: row[:owner_id],
                    created_at: Time.now,
                    updated_at: Time.now
                  }
                )
            end
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

  GitHub::Transitions::BackfillOrgOwnedPrivateNetworksWithForks.new(args).run
end
