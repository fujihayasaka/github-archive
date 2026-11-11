# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills the Created, Updated, and Closed system-defined columns for all
# existing Memex projects. New projects already receive these columns via the
# SYSTEM_DEFINED_COLUMNS constant, but projects created before this change
# need to be backfilled.
#
# For each project we:
#   - Skip columns where the system-defined data type already exists.
#   - Rename any user-defined column with a conflicting name (e.g. "Created"
#     becomes "Created-old") and then create the new system column.
#   - Only insert the missing columns.
#
# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSystemDateMemexProjectColumns < Base
      COLUMN_DEFINITIONS = T.let([
        {
          name: MemexProjectColumn::CREATED_COLUMN_NAME,
          data_type: :created,
        },
        {
          name: MemexProjectColumn::UPDATED_COLUMN_NAME,
          data_type: :updated,
        },
        {
          name: MemexProjectColumn::CLOSED_COLUMN_NAME,
          data_type: :closed,
        },
      ].freeze, T::Array[T::Hash[Symbol, T.untyped]])

      iterate_over :database_table, params: {
        model_class: MemexProject,
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        projects = MemexProject
          .where(id: items.keys)
          .includes(:memex_project_columns)
          .index_by(&:id)

        columns_to_create = T.let([], T::Array[MemexProjectColumn])
        columns_to_rename = T.let([], T::Array[MemexProjectColumn])

        projects.each do |memex_project_id, memex_project|
          existing_columns = memex_project.columns
          last_position = T.let(existing_columns.map(&:position).max.to_i, Integer)

          COLUMN_DEFINITIONS.each do |definition|
            column_name = T.cast(definition[:name], String)
            data_type = definition[:data_type]

            system_exists = existing_columns.any? { |c| c.data_type == data_type.to_s }

            if system_exists
              log("Project #{memex_project_id} already has a system-defined #{column_name} column")
              next
            end

            conflicting_column = existing_columns.find { |c| c.user_defined? && c.name.casecmp?(column_name) }
            if conflicting_column
              log("Project #{memex_project_id} has a user-defined #{column_name} column, will rename to #{column_name}-old")
              columns_to_rename << conflicting_column
            end

            last_position += 1
            columns_to_create << memex_project.memex_project_columns.build(
              name: column_name,
              data_type: data_type,
              visible: false,
              position: last_position,
              user_defined: false,
              name_slug: MemexProjectColumn.generate_name_slug(column_name),
            )
          end
        end

        return if columns_to_create.empty?

        if dry_run?
          created_columns = columns_to_create.map do |column|
            "#{column.name} for project #{column.memex_project_id}"
          end
          log("Would have created the following columns:\n#{created_columns.join("\n")}") if verbose?
        else
          columns_to_rename.group_by(&:name).each do |name, columns|
            old_name = "#{name}-old"
            old_slug = MemexProjectColumn.generate_name_slug(old_name)
            write_to(model_class: MemexProjectColumn) do
              MemexProjectColumn.where(id: columns.map(&:id)).update_all(
                name: old_name,
                name_slug: old_slug,
              )
            end
            log("Renamed #{columns.size} column(s) named #{name} to #{old_name}")
          end

          columns_to_create.each do |column|
            write_to(model_class: MemexProjectColumn) do
              column.save!
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

  GitHub::Transitions::BackfillSystemDateMemexProjectColumns.new(args).run
end
