# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ArtifactDeploymentRecordsOwnerIdColBackfill < Base
      class ArtifactDeploymentRecord < ApplicationRecord::Domain::ArtifactRegistry
        self.table_name = :artifact_deployment_records
        belongs_to :artifact_metadata
      end

      iterate_over :database_table, params: {
        model_class: ArtifactDeploymentRecord,
        columns: %i[owner_id],
        conditions: "owner_id IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        record_ids = items.keys
        log "Processing #{record_ids.size} deployment records"

        if dry_run?
          log "Would set owner_id for #{record_ids.size} deployment records based on artifact_metadata"
          return
        end

        write_to(model_class: ArtifactDeploymentRecord) do
          ArtifactDeploymentRecord
            .joins(:artifact_metadata)
            .where(id: record_ids)
            .update_all("artifact_deployment_records.owner_id = artifact_metadata.owner_id")
        end

        log "Finished batch", size: items.size
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

  GitHub::Transitions::ArtifactDeploymentRecordsOwnerIdColBackfill.new(args).run
end
