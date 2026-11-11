# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class MoveMaxRefUpdatesToConfig < Base

      class KeyValues < ApplicationRecord::Domain::KeyValues
        self.table_name = "key_values"
      end

      class ConfigurationEntries < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = "configuration_entries"
      end

      iterate_over :database_table, params: {
        model_class: KeyValues,
        columns: [:key, :value, :created_at, :updated_at],
        conditions: "key_values.key LIKE 'repo.max_ref_updates.%'"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        rows = items.map { |item| item[1] }
        rows_to_insert = rows.map do |row|
          {
            target_id: row[:key].split(".").last,
            target_type: "Repository",
            name: "max_ref_updates",
            value: row[:value],
            updater_id: User.ghost.id,
            created_at: row[:created_at],
            updated_at: row[:updated_at],
            final: true
          }
        end
        existing_repo_ids = Repository.where(id: rows_to_insert.map { |row| row[:target_id] }).pluck(:id)
        rows_to_insert = rows_to_insert.select { |row| existing_repo_ids.include?(row[:target_id].to_i) }

        if dry_run?
          log "Would have inserted ConfigurationEntries for Repositories with ids: #{rows_to_insert.map { |row| row[:target_id] }}" if verbose?
          return
        end

        log "Inserting ConfigurationEntries for Repositories with ids: #{rows_to_insert.map { |row| row[:target_id] }}" if verbose?
        write_to(model_class: ConfigurationEntries) do
          rows_to_insert.each do |row|
            ConfigurationEntries.insert_all([row])
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

  GitHub::Transitions::MoveMaxRefUpdatesToConfig.new(args).run
end
