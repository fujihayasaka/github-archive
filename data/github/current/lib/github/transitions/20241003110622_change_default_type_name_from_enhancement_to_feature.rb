# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ChangeDefaultTypeNameFromEnhancementToFeature < Base

      class IssueType < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :issue_types
      end

      iterate_over :database_table, params: {
        model_class: IssueType,
        # getting all rows where the name is 'Enhancement',
        conditions: "name = 'Enhancement'",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        issue_types_attributes = ActiveRecord::Base.connected_to(role: :reading) do
          IssueType.where(id: items.keys).map do |issue_type|
            owner = Organization.find_by(id: issue_type.owner_id)
            if !owner
              log "Skipping issue type #{issue_type.id} because owner is missing"
              next
            end
            {
              id: issue_type.id,
              name: "Feature",
              color: issue_type.color,
              description: issue_type.description,
              enabled: issue_type.enabled,
              issue_type: issue_type.issue_type,
              owner_id: issue_type.owner_id,
              updated_at: Time.current,
            }
          end
        end.compact

        if dry_run?
          log "Dry run: would update the following issue types: #{issue_types_attributes.pluck(:id).join(', ')}"
          log "Dry run: count of issue types to update: #{issue_types_attributes.size}"
        else
          write_to(model_class: IssueType) do
            # rubocop:disable GitHub/UpsertAll
            IssueType.upsert_all(issue_types_attributes)
          end
          log "Updated issue types: #{issue_types_attributes.pluck(:id).join(', ')}"
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

  GitHub::Transitions::ChangeDefaultTypeNameFromEnhancementToFeature.new(args).run
end
