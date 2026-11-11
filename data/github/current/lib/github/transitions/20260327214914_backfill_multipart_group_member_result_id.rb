# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
#
# Backfills result_id = token_scan_result_id for all existing rows in
# secret_scanning_validation_multipart_group_members where result_id is still
# the default (0) and is_supplementary = 0 (i.e. regular token_scan_results rows).
#
# This is safe to re-run (idempotent) and supports resumption via --start_id / --end_id.
#
# The table is ~60K rows, so this should complete quickly.
#
# Usage:
#   # Dry run (default)
#   bin/safe-ruby lib/github/transitions/20260327214914_backfill_multipart_group_member_result_id.rb --verbose
#
#   # Real run
#   bin/safe-ruby lib/github/transitions/20260327214914_backfill_multipart_group_member_result_id.rb --verbose -w
module GitHub
  module Transitions
    class BackfillMultipartGroupMemberResultId < Base
      class MultipartGroupMember < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :secret_scanning_validation_multipart_group_members
      end

      iterate_over :database_table, params: {
        model_class: MultipartGroupMember,
        conditions: "result_id = 0 AND is_supplementary = 0",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log("would update #{items.count} rows: set result_id = token_scan_result_id")
          return
        end

        write_to(model_class: MultipartGroupMember) do
          MultipartGroupMember
            .where(id: items.keys)
            .where(result_id: 0, is_supplementary: 0)
            .update_all(Arel.sql("result_id = token_scan_result_id"))
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

  GitHub::Transitions::BackfillMultipartGroupMemberResultId.new(args).run
end
