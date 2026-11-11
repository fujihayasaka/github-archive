# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills users.soft_deleted_at with the created_at value from soft_deleted_organizations
# for all organizations that have a soft_deleted_organizations record.
module GitHub
  module Transitions
    class BackfillOrgSoftDeletedCreatedAtToUsersSoftDeletedAt < Base
      # Inline model for the legacy table — the global SoftDeletedOrganization model
      # has been removed but this transition still needs to iterate the table on GHES.
      class LegacySoftDeletedOrganization < ApplicationRecord::Domain::Users
        self.table_name = "soft_deleted_organizations"
      end

      iterate_over :database_table, params: {
        model_class: LegacySoftDeletedOrganization,
        columns: %i[organization_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        GitHub::CurrentTenant.unscope do
          organization_ids = items.values.map { |cols| cols[:organization_id] }

          scope = User.where(id: organization_ids, soft_deleted_at: nil)
            .joins("INNER JOIN soft_deleted_organizations ON soft_deleted_organizations.organization_id = users.id")

          if dry_run?
            count = scope.count
            log "Would update #{count} user(s) with soft_deleted_at" if count > 0
          else
            updated_count = 0
            write_to(model_class: User) do
              updated_count = T.cast(
                scope.update_all("users.soft_deleted_at = soft_deleted_organizations.created_at"),
                Integer,
              )
            end
            log "Updated #{updated_count} user(s) with soft_deleted_at - row(s) (#{organization_ids.min}-#{organization_ids.max})" if updated_count > 0
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

  GitHub::Transitions::BackfillOrgSoftDeletedCreatedAtToUsersSoftDeletedAt.new(args).run
end
