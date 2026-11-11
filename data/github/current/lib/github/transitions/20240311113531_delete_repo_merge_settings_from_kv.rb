# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteRepoMergeSettingsFromKv < Base
      class KeyValue < ApplicationRecord::Domain::KeyValues
        self.table_name = :key_values
      end

      iterate_over :database_table, params: {
        model_class: KeyValue,
        conditions: "(`key` LIKE 'repo.merge_commit_blocked.%' OR `key` LIKE 'repo.squash_merge_blocked.%' OR `key` LIKE 'repo.rebase_merge_blocked.%')",
        columns: %i[key],
      }


      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if verbose?
          keys = items.values.map { _1[:key] }
          log("#{items.size} entries to expire: #{keys.join(", ")}")
        end

        sql = Arel.sql(
          "UPDATE `key_values` SET `expires_at` = :expires_at WHERE `id` IN (:ids)",
          expires_at: 7.days.from_now,
          ids: items.keys,
        )

        updated = T.let(0, Integer)
        unless dry_run?
          write_to(model_class: KeyValue) do
            updated = KeyValue.connection.update(sql)
          end
        end

        log("#{updated} entries updated") if verbose?
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

  GitHub::Transitions::DeleteRepoMergeSettingsFromKv.new(args).run
end
