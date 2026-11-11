# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills the polymorphic owner_id/owner_type columns on vulnerabilities
# from the legacy owner_business_id and owner_org_id columns.
# See PR #433453 for context.
module GitHub
  module Transitions
    class BackfillVulnerabilitiesOwnerId < Base
      class VulnerabilityRecord < ApplicationRecord::Notify
        self.table_name = :vulnerabilities
      end

      iterate_over :database_table, params: {
        model_class: VulnerabilityRecord,
        conditions: "(owner_business_id IS NOT NULL OR owner_org_id IS NOT NULL) AND owner_id IS NULL",
        columns: %i[owner_business_id owner_org_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        business_ids = []
        org_ids = []

        items.each do |id, cols|
          if cols[:owner_business_id].present?
            business_ids << id
          elsif cols[:owner_org_id].present?
            org_ids << id
          end
        end

        log "#{dry_run? ? "Would update" : "Updating"} #{business_ids.size} business-owned and #{org_ids.size} org-owned records (IDs #{items.keys.first}..#{items.keys.last})"
        return if dry_run?

        if business_ids.any?
          write_to(model_class: VulnerabilityRecord) do
            VulnerabilityRecord.where(id: business_ids)
              .update_all("owner_id = owner_business_id, owner_type = 'Business'")
          end
        end

        if org_ids.any?
          write_to(model_class: VulnerabilityRecord) do
            VulnerabilityRecord.where(id: org_ids)
              .update_all("owner_id = owner_org_id, owner_type = 'User'")
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

  GitHub::Transitions::BackfillVulnerabilitiesOwnerId.new(args).run
end
