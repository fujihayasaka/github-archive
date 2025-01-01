# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# This template is for a transition ROLLBACK.
# This should only be run in the event that Github::Transitions::SetMeteredTrueForMeteredProducts
# causes impact and you need to immediately reset all data to its pre-transition state.
# Some questions to ask yourself as you implement your rollback:
#   - Could any of this data have changed between the time the transition ran, and the time it is rolled back?
#   - How long will your transition take to run?
#   - Is ALL data that was changed by your transition included in this rollback?
module GitHub
  module Transitions
    class SetMeteredTrueForMeteredProductsRollback < Transition
      MAX_THROTTLE_RETRIES = 4

      def perform
        CSV.foreach(rollback_filename, headers: false) { |row| roll_back_row(row) }
      end

      def roll_back_row(row)
        id = row

        ActiveRecord::Base.connected_to(role: :writing) do
          metered_product = ::Billing::ProductUUID.find_by(id: id)
          if metered_product.present?
            ::Billing::ProductUUID.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              metered_product.update!(metered: false) unless dry_run?
            end
          else
            log "Could not find ::Billing::ProductUUID with id #{id}, skipping"
          end
        end
      end

      private

      def rollback_filename
        @other_args[:data_file]
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:dry_run] = false
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("-d", "--data_file FILE", "Path to a file containing rollback data") do |file|
      options[:data_file] = file
    end

    opts.on("-s", "--start_id ID", "ID to start processing") do |id|
      options[:start_id] = id.to_i
    end

    opts.on("-e", "--end_id ID", "ID to end processing") do |id|
      options[:end_id] = id.to_i
    end

    opts.on("-n", "--workers COUNT", "Worker count") do |count|
      options[:workers] = count.to_i
    end
  end.parse!

  options[:dry_run] ||= true
  options[:workers] ||= 1

  transition = GitHub::Transitions::SetMeteredTrueForMeteredProductsRollback.new(**options)
  transition.run
end
