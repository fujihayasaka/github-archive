# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class TruncateMemexProjectIterationTitles < Base
      iterate_over :database_table, params: {
        model_class: MemexProjectColumn,
        conditions: "data_type = 64",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |memex_project_column_id|
          memex_project_column = MemexProjectColumn.find_by(id: memex_project_column_id)
          next if memex_project_column.blank?

          settings = memex_project_column.settings.dup
          next if settings.blank?

          iterations_modified = false
          completed_iterations_modified = false

          if (iterations = settings.dig("configuration", "iterations"))
            modified_iterations = iterations.collect do |iteration|
              truncate_iteration(iteration)
            end

            iterations_modified = modified_iterations.any?
          end

          if (completed_iterations = settings.dig("configuration", "completed_iterations"))
            modified_completed_iterations = completed_iterations.collect do |iteration|
              truncate_iteration(iteration)
            end

            completed_iterations_modified = modified_completed_iterations.any?
          end

          unless iterations_modified || completed_iterations_modified
            log "MemexProjectColumn with 'iteration' data_type for MemexProject '#{memex_project_column.memex_project_id}' does not have any changes to save for the settings column, skipping"
            next
          end

          log "MemexProjectColumn with 'iteration' data_type for MemexProject '#{memex_project_column.memex_project_id}' has changes to the settings column"
          next if dry_run?

          write_to(model_class: MemexProjectColumn) do
            if memex_project_column.update(settings:)
              log "Updated MemexProjectColumn with id '#{memex_project_column.id}' successfully" if verbose?
            else
              log "Could not save MemexProjectColumn with id '#{memex_project_column.id}': #{memex_project_column.errors.inspect}"
            end
          end
        end
      end

      private

      sig { params(iteration: T::Hash[T.untyped, T.untyped]).void }
      def truncate_iteration(iteration)
        return false unless (original_title = iteration["title"])
        return false unless original_title.length > 500

        truncated_title = original_title[...500]
        iteration["title"] = truncated_title

        if iteration.key?("title_html")
          iteration["title_html"] = GitHub::Goomba::MemexTextColumnPipeline.to_html(truncated_title)
        end

        true
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

  GitHub::Transitions::TruncateMemexProjectIterationTitles.new(args).run
end
