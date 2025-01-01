# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillMemexProjectLastVisitedOnDate < Base
      iterate_over :database_table, params: {
        model_class: MemexProject,
        columns: %i[id last_visited_on],
        conditions: "last_visited_on IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_project_id|
          memex_project = MemexProject.find_by(id: memex_project_id)
          next if memex_project.blank?

          if dry_run?
            log("Would have backfilled last_visited_on date column for project #{memex_project_id}")
            next
          end

          write_to(model_class: MemexProject) do
            if (last_visited_on = memex_project.memex_project_visits.maximum(:last_visited_at)&.to_date)
              updated = memex_project.update_columns(last_visited_on:)

              if updated
                log("Set the last_visited_on for project #{memex_project_id} to #{last_visited_on}")
              else
                log("Could not set the last_visited_on column for project #{memex_project_id} to #{last_visited_on}")
              end
            else
              log("Project #{memex_project_id} does not have any visits, skipping")
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

  GitHub::Transitions::BackfillMemexProjectLastVisitedOnDate.new(args).run
end
