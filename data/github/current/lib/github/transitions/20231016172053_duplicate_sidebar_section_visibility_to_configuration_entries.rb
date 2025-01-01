# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class DuplicateSidebarSectionVisibilityToConfigurationEntries < Base

      class KeyValues < ApplicationRecord::Domain::KeyValues
        self.table_name = "key_values"
      end

      class ConfigurationEntries < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      VALID_NAMES = T.let(
        %w[
        deployments_sidebar_section_enabled
        environments_sidebar_section_enabled
        packages_sidebar_section_enabled
        pages_url_sidebar_section_enabled
        releases_sidebar_section_enabled
        ],
        T::Array[String]
      )

      iterate_over :database_table, params: {
        model_class: KeyValues,
        columns: [:key, :value, :created_at, :updated_at],
        conditions: "key_values.key LIKE 'repo:sidebar_section_visibility:%'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        rows = items.map { |item| item[1] }

        rows_to_insert = []
        rows.each do |row|
          insert_data = {
            target_id: row[:key].split(":").last,
            target_type: "Repository",
            updater_id: User.ghost.id,
            created_at: row[:created_at],
            updated_at: row[:updated_at],
            final: true
          }
          begin
            sidebar_sections = JSON.parse(row[:value])
          rescue Yajl::ParseError
            # If we cannot parse a row, just move on
            next
          end
          sidebar_sections.keys.each do |key|
            name = "#{key}_sidebar_section_enabled"
            value = case sidebar_sections[key]
            when "0"
              "false"
            when "1"
              # Since we default to enabled if no configuration_entry is found anyway, there is no use backfilling
              # values of "1" (true) for the sidebar sections
              nil
            else
              nil
            end

            if value && VALID_NAMES.include?(name)
              rows_to_insert << insert_data.merge(name: name, value: value) unless value.nil?
            end
          end
        end

        existing_repo_ids = Repository.where(id: rows_to_insert.map { |row| row[:target_id] }).pluck(:id)
        rows_to_insert = rows_to_insert.select { |row| existing_repo_ids.include?(row[:target_id].to_i) }

        if dry_run?
          log "Would have inserted ConfigurationEntries for Repositories with ids: #{rows_to_insert.map { |row| row[:target_id] }}" if verbose?
          return
        end

        log "Inserting ConfigurationEntries for Repositories with ids: #{rows_to_insert.map { |row| row[:target_id] }}" if verbose?

        rows_to_insert.each do |row|
          if ConfigurationEntries.exists?(target_id: row[:target_id], target_type: "Repository", name: row[:name])
            write_to(model_class: ConfigurationEntries) do
              ConfigurationEntries.where(target_id: row[:target_id], target_type: "Repository", name: row[:name]).update_all(row)
            end
          else
            write_to(model_class: ConfigurationEntries) do
              ConfigurationEntries.insert(row)
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

  GitHub::Transitions::DuplicateSidebarSectionVisibilityToConfigurationEntries.new(args).run
end
