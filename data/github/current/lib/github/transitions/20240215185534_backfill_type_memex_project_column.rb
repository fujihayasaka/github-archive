# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillTypeMemexProjectColumn < Base
      iterate_over :database_table, params: {
        model_class: MemexProject,
        conditions: "owner_type = 'Organization'",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_project_id|
          memex_project = MemexProject.find_by(id: memex_project_id)
          next if memex_project.blank?

          # This check is done in the backfill_issue_type_column method, but want to cache it or return early in the
          # read-only connection.
          existing_issue_type_column = memex_project.columns.any?(&:issue_type?)
          if existing_issue_type_column
            log("Skipping project #{memex_project_id} because it already has a system-defined Type column")
            next
          end

          existing_user_defined_type_column = memex_project.columns.any? do |column|
            column.user_defined? && column.name.casecmp?(MemexProjectColumn::TYPE_COLUMN_NAME)
          end
          if existing_user_defined_type_column
            log("Skipping project #{memex_project_id} because it already has a user-defined Type column")
            next
          end

          if dry_run?
            log("Would have created a Type column for project #{memex_project_id}")
            next
          end

          write_to(model_class: MemexProjectColumn) do
            issue_type_column = memex_project.backfill_issue_type_column(
              queue_reindex_project_items_after_create_commit: false,
            )

            if issue_type_column.persisted?
              log("Created a Type column for project #{memex_project_id}")
            else
              log("Error creating a Type column for project #{memex_project_id}")
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

  GitHub::Transitions::BackfillTypeMemexProjectColumn.new(args).run
end
