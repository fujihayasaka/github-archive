# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220329172157_create_copilot_product_in_zuora.rb --verbose | tee -a /tmp/create_copilot_product_in_zuora.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220329172157_create_copilot_product_in_zuora.rb --verbose -w | tee -a /tmp/create_copilot_product_in_zuora.log
#
module GitHub
  module Transitions
    class CreateCopilotProductInZuora < Transition
      include GitHub::Billing::ZuoraProduct::ZuoraSettings
      # #dotcom-db-migration-help is your friend, and can help code review
      # transitions before they're run to make sure they're being nice to our
      # database clusters. We're usually looking for a few things in transitions:
      #   1. Iterators: We want to query the database for records to change in batches
      #   2. Read-Only Replicas: If we're reading data to be changed, we want to do it on
      #      the read-only replicas to keep load off the primary.
      #   3. Throttle writes: We want to make sure we wrap any actual writes to the primary
      #      in a `throttle_with_retry` block, which should be called on the most specific
      #      `ApplicationRecord::*` class/subclass or object. This will make sure we don't
      #      overwhelm primary and cause replication lag.
      #   4. Efficient queries: We want to avoid massive table scans, so make sure your
      #      query has an index or is performant and safe without one.
      #
      #   For more information on all this, checkout the transition docs at
      #   https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/transitions/

      PRODUCT_TYPE = "github.copilot"
      PRODUCT_KEY  = "v0"

      # Expect these to be provided by Product Teams
      # TODO: Set these in a method to not trigger an HTTP call to update exchange rates
      MONTHLY_UNIT_PRICE = ::Billing::Money.new(10 * 100)
      YEARLY_UNIT_PRICE = ::Billing::Money.new(100 * 100)

      # Returns nothing.
      def perform
        return unless GitHub.billing_enabled?
        log "Syncing - GitHub Copilot"
        GitHub.zuorest_client.timeout = 60

        # For individuals
        if existing_copilot_for_individuals_product_uuid?
          log "Monthly and Yearly ProductUUIDs found for `GitHub Copilot`"
        else
          create_copilot_for_individuals_product unless dry_run?
        end
      end

      private

      def create_copilot_for_individuals_product
        GitHub::Billing::ZuoraProduct.create(
          product_type: PRODUCT_TYPE,
          product_key: PRODUCT_KEY,
          product_name: "GitHub Copilot",
          charges: [{
            type: :flat,
            prices: { ::User::BillingDependency::YEARLY_PLAN.to_sym => YEARLY_UNIT_PRICE.dollars, ::User::BillingDependency::MONTHLY_PLAN.to_sym => MONTHLY_UNIT_PRICE.dollars }
          }]
        )
      rescue Zuorest::HttpError => e
        log "Error when attempting to sync GitHub Copilot to Zuora, see details:"
        log e.inspect
        log e.data
      ensure
        msg  = existing_copilot_for_individuals_product_uuid? ? "was successful" : "failed"
        log "Sync for `GitHub Copilot` #{msg}"
      end

      def existing_copilot_for_individuals_product_uuid?
        scope = ::Billing::ProductUUID.where(product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY)
        scope.where(billing_cycle: ::User::BillingDependency::MONTHLY_PLAN).exists? && scope.where(billing_cycle: ::User::BillingDependency::YEARLY_PLAN).exists?
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

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end

    opts.on("-n", "--workers", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:workers] ||= 1
  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::CreateCopilotProductInZuora.new(**options)
  transition.run
end
