# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveRepoMergeSettingsFromKvToConfiguration < Base
      MERGE_METHOD_MAP = T.let({
        "merge_commit_blocked" => Configurable::MergeCommits::KEY,
        "squash_merge_blocked" => Configurable::SquashCommits::KEY,
        "rebase_merge_blocked" => Configurable::RebaseCommits::KEY,
      }, T::Hash[String, String])

      class KeyValue < ApplicationRecord::Domain::KeyValues
        self.table_name = :key_values
      end

      class ConfigurationEntry < ApplicationRecord::Domain::ConfigurationEntries
        self.table_name = :configuration_entries
      end

      iterate_over :database_table, params: {
        model_class: KeyValue,
        conditions: MERGE_METHOD_MAP.keys.map { "(`key` LIKE 'repo.#{_1}.%')" }.join(" OR "),
        columns: %i[key value created_at updated_at],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        settings = items.values.
          select { _1[:value] == "true" }.
          map do |row|
            _, merge_method, repo_id = row[:key].split(".")
            [MERGE_METHOD_MAP.fetch(merge_method), repo_id.to_i, row[:created_at], row[:updated_at]]
          end

        log("#{settings.size} configuration entries to write ...")
        if verbose?
          settings.each do |config_key, repo_id, _, _|
            log("- #{config_key} for #{repo_id}")
          end
        end
        return if dry_run?
        return if settings.size.zero?

        # NOTE: The value of these settings is always "true", so the
        #  `ON DUPLICATE KEY UPDATE` clause is an intentional no-op.
        query = <<-SQL
          INSERT INTO `configuration_entries`
          (`target_id`, `target_type`, `updater_id`, `name`, `value`,
            `final`, `created_at`, `updated_at`)
          :rows
          ON DUPLICATE KEY UPDATE `value` = 'true'
        SQL

        # We don't have any information about the actor who updated the
        #  KV records, so we use `ghost` as a placeholder.
        user = User.ghost
        rows = settings.map do |config_key, repo_id, created_at, updated_at|
          [repo_id, "Repository", user.id, config_key, "true", false, created_at, updated_at]
        end
        sql = Arel.sql(query, rows: Arel::Nodes::ValuesList.new(rows))

        write_to(model_class: ConfigurationEntry) do
          ConfigurationEntry.connection.insert(sql)
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

  GitHub::Transitions::MoveRepoMergeSettingsFromKvToConfiguration.new(args).run
end
