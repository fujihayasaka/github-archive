# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ZeroOutLfsDatapacks < Base
      class AssetStatus < ApplicationRecord::Domain::Assets
        self.table_name = :asset_statuses
      end

      iterate_over :database_table, params: {
        model_class: AssetStatus,
        columns: %i[id owner_id data_packs asset_packs],
        conditions: "data_packs > 0 OR asset_packs > 0",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        user_ids = items.values.map { |item| item[:owner_id] }
        log("Number of user_ids in the batch: #{user_ids.size}")

        user_ids.each do |user_id|
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

  GitHub::Transitions::ZeroOutLfsDatapacks.new(args).run
end
