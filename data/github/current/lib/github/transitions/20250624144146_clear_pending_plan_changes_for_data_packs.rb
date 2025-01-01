# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ClearPendingPlanChangesForDataPacks < Base
      class PendingPlanChange < ApplicationRecord::Domain::Integrations
        self.table_name = :pending_plan_changes
      end

      iterate_over :database_table, params: {
        model_class: PendingPlanChange,
        conditions: "data_packs > 0 AND is_complete = false",
        columns: %i[id data_packs user_id is_complete],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        user_ids = items.values.map { |item| item[:user_id] }
        log("Number of user_ids in the batch: #{user_ids.uniq.size}")

        user_ids.uniq.each do |user_id|
          if dry_run?
            log("Would schedule Billing::ZeroOutLfsDatapacksJob for user_id: #{user_id}")
          else
            log("Scheduling Billing::ZeroOutLfsDatapacksJob for user_id: #{user_id}")
            ::Billing::ZeroOutLfsDatapacksJob.perform_later(user_id)
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

  GitHub::Transitions::ClearPendingPlanChangesForDataPacks.new(args).run
end
