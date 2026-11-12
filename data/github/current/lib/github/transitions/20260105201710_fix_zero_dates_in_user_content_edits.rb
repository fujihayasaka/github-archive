# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout this documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
#
# GHES instances upgrading from older versions can have `'0000-00-00 00:00:00'`
# stored in the datetime columns of `user_content_edits`. The migration that
# widens the integer columns (`20260105201711_widen_user_content_edit_columns`)
# performs a `change_table bulk: true`, which triggers a full ALTER TABLE row
# rewrite. Under MySQL strict mode those invalid zero-dates are rejected with
# error 1292, failing the migration.
#
# This transition runs before that migration and rewrites the invalid zero-date
# values to valid ones:
#   - `edited_at` is set to `created_at` (its best semantic match)
#   - `created_at` / `updated_at` are set to `'1970-01-01 00:00:01'`
#
# On dotcom this is a no-op (no zero-date rows exist), so it only matters for
# GHES upgrades. See https://github.com/github/ghes/issues/18630.
module GitHub
  module Transitions
    class FixZeroDatesInUserContentEdits < Base
      ZERO_DATE = T.let("0000-00-00 00:00:00", String)
      REPLACEMENT_DATE = T.let("1970-01-01 00:00:01", String)

      class UserContentEdit < ApplicationRecord::Domain::UserContentEdits
        self.table_name = :user_content_edits
      end

      iterate_over :database_table, params: {
        model_class: UserContentEdit,
        conditions: <<~SQL.squish,
          CAST(`created_at` AS CHAR) = '#{ZERO_DATE}'
          OR CAST(`updated_at` AS CHAR) = '#{ZERO_DATE}'
          OR CAST(`edited_at` AS CHAR) = '#{ZERO_DATE}'
        SQL
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys

        if dry_run?
          log "would fix zero-dates for #{ids.size} user_content_edits rows"
          return
        end

        log "fixing zero-dates for #{ids.size} user_content_edits rows"

        ids.each_slice(500) do |batch|
          write_to(model_class: UserContentEdit) do
            UserContentEdit.where(id: batch).update_all(<<~SQL.squish)
              `edited_at` = CASE
                WHEN CAST(`edited_at` AS CHAR) = '#{ZERO_DATE}'
                THEN CASE
                  WHEN CAST(`created_at` AS CHAR) = '#{ZERO_DATE}'
                  THEN '#{REPLACEMENT_DATE}'
                  ELSE `created_at`
                END
                ELSE `edited_at`
              END,
              `created_at` = CASE
                WHEN CAST(`created_at` AS CHAR) = '#{ZERO_DATE}'
                THEN '#{REPLACEMENT_DATE}'
                ELSE `created_at`
              END,
              `updated_at` = CASE
                WHEN CAST(`updated_at` AS CHAR) = '#{ZERO_DATE}'
                THEN CASE
                  WHEN CAST(`created_at` AS CHAR) = '#{ZERO_DATE}'
                  THEN '#{REPLACEMENT_DATE}'
                  ELSE `created_at`
                END
                ELSE `updated_at`
              END
            SQL
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

  GitHub::Transitions::FixZeroDatesInUserContentEdits.new(args).run
end
