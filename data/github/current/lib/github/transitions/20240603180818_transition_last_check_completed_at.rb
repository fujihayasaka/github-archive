# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class TransitionLastCheckCompletedAt < Base

      class TokenScanResultsValidation < ApplicationRecord::Domain::TokenScanningService
        self.table_name = :token_scan_results_validation
      end

      iterate_over :database_table, params: {
        model_class: TokenScanResultsValidation,
        columns: %i[last_checked last_check_completed_at],
        conditions: "last_check_completed_at IS NULL"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log("would update #{items.count} token_scan_result_validation_records")
          return
        end

        # Just set last_check_completed_at to last_checked. last_checked is not nullable, so everything in this table
        # will have a last_checked record
        write_to(model_class: TokenScanResultsValidation) do
          TokenScanResultsValidation
            .where(id: items.keys)
            .update_all(Arel.sql("last_check_completed_at = last_checked"))
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

  GitHub::Transitions::TransitionLastCheckCompletedAt.new(args).run
end
