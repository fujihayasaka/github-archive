# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class AdvancedSecurityMonthlyTrialDoesNotBillOnExpiration < Transition
      class ProductUUID < ApplicationRecord::Domain::Users
        self.table_name = :product_uuids
      end

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore}"

        advanced_security_product_count = readonly do
          ProductUUID.where(product_type: "github.advanced_security").count
        end

        if advanced_security_product_count != 1
          log "advanced_security product count is #{advanced_security_product_count}!"
          return
        end

        advanced_security_monthly = readonly do
          ProductUUID.find_by(product_type: "github.advanced_security")
        end

        if advanced_security_monthly.nil?
          log "advanced_security_monthly product not found!"
          return
        end

        log "found advanced security monthly product."

        if dry_run?
          log "Will update product to not bill on expiration"
          return
        end

        if advanced_security_monthly.bill_on_trial_expiration == false
          log "Product already does not bill on trial expiration. Skipping transition"
          return
        end

        if advanced_security_monthly.update(bill_on_trial_expiration: false)
          log "Updated product to not bill on expiration"
        else
          log "Failed to update product to not bill on expiration"
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::AdvancedSecurityMonthlyTrialDoesNotBillOnExpiration.new(**options)
  transition.run
end
