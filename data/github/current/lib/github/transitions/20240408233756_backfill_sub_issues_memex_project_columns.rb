# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSubIssuesMemexProjectColumns < Base
      iterate_over :database_table, params: {
        model_class: MemexProject,
      }

      sig { params(column: MemexProjectColumn, unhandled_projects: T::Set[Integer]).returns(T::Boolean) }
      def is_parent_issue_column?(column, unhandled_projects)
        system_parent_issue = column.parent_issue?
        user_parent_issue = column.name.casecmp?(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME) && column.user_defined?

        if system_parent_issue || user_parent_issue
          log("Project #{column.memex_project_id} already contains a parent issue column")
          unhandled_projects.add(column.memex_project_id) if user_parent_issue
          return true
        end

        false
      end

      sig { params(column: MemexProjectColumn, unhandled_projects: T::Set[Integer]).returns(T::Boolean) }
      def is_sub_issues_progress_column?(column, unhandled_projects)
        system_sub_issues_progress = column.sub_issues_progress?
        user_sub_issues_progress = column.name.casecmp?(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME) && column.user_defined?

        if system_sub_issues_progress || user_sub_issues_progress
          log("Project #{column.memex_project_id} already contains a sub-issues progress column")
          unhandled_projects.add(column.memex_project_id) if user_sub_issues_progress
          return true
        end

        false
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        columns_to_insert = []
        unhandled_projects = Set.new # To reference after the transition runs

        items.keys.each do |memex_project_id|
          memex_project = MemexProject.find_by(id: memex_project_id)
          next if memex_project.blank?

          # Check for existing Parent issue and/or Sub-issues progress columns
          parent_issue_exists = T.let(false, T::Boolean)
          sub_issues_progress_exists = T.let(false, T::Boolean)

          memex_project.columns.each do |column|
            if is_parent_issue_column?(column, unhandled_projects)
              parent_issue_exists = true
            elsif is_sub_issues_progress_column?(column, unhandled_projects)
              sub_issues_progress_exists = true
            end
          end

          # Skip project entirely if both exist
          if parent_issue_exists && sub_issues_progress_exists
            log("Skipping project #{memex_project_id} because it already contains both sub-issues columns")
            next
          end

          # Otherwise, add missing columns to array for bulk insertion
          last_position = T.let(memex_project.memex_project_columns.maximum(:position) + 1, Integer)
          unless parent_issue_exists
            log("Creating a Parent issue column for project #{memex_project_id}")
            columns_to_insert.push({
              memex_project_id: memex_project_id,
              name: MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME,
              data_type: :parent_issue,
              visible: false,
              position: last_position,
              user_defined: false,
              # from /packages/planning/app/models/memex_project_column.rb#L553
              name_slug: MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME.downcase.gsub(" ", "-"),
            })
            last_position += 1
          end

          unless sub_issues_progress_exists
            log("Creating a Sub-issues progress column for project #{memex_project_id}")
            columns_to_insert.push({
              memex_project_id: memex_project_id,
              name: MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME,
              data_type: :sub_issues_progress,
              visible: false,
              position: last_position,
              user_defined: false,
              # from /packages/planning/app/models/memex_project_column.rb#L553
              name_slug: MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME.downcase.gsub(" ", "-"),
            })
          end
        end

        if dry_run?
          created_columns = columns_to_insert.map do |column|
            "#{column[:name]} for project #{column[:memex_project_id]}"
          end
          log("Would have created the following columns:\n#{created_columns.to_a.join("\n")}")
        else
          write_to(model_class: MemexProjectColumn) do
            MemexProjectColumn.insert_all(columns_to_insert)
          end
        end

        unless unhandled_projects.empty?
          log("The following projects were not properly backfilled for sub-issues:\n#{unhandled_projects.to_a.join("\n")}")
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

  GitHub::Transitions::BackfillSubIssuesMemexProjectColumns.new(args).run
end
