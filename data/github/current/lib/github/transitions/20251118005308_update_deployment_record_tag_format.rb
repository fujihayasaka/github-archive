# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateDeploymentRecordTagFormat < Base
      class ArtifactDeploymentRecordTag < ApplicationRecord::Domain::ArtifactRegistry
        self.table_name = :artifact_deployment_record_tags
      end

      iterate_over :database_table, params: {
        model_class: ArtifactDeploymentRecordTag,
        conditions: "tag_name IN ('critical-resource', 'internet-exposed', 'lateral-movement', 'sensitive-data')",
        columns: %i[tag_name],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        scope = ArtifactDeploymentRecordTag.where(id: items.keys)

        if dry_run?
          log "would update #{scope.count} rows"
        else
          write_to(model_class: ArtifactDeploymentRecordTag) do
            scope.update_all(Arel.sql("tag_value = tag_name, tag_name = 'runtime-risk'"))
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

  GitHub::Transitions::UpdateDeploymentRecordTagFormat.new(args).run
end
