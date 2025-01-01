# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221003032841_create_git_hub_advanced_security_in_zuora.rb --verbose | tee -a /tmp/create_git_hub_advanced_security_in_zuora.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221003032841_create_git_hub_advanced_security_in_zuora.rb --verbose -w | tee -a /tmp/create_git_hub_advanced_security_in_zuora.log
module GitHub
  module Transitions
    class CreateGitHubAdvancedSecurityInZuora < Transition

      PRODUCT_TYPE = "github.advanced_security"
      PRODUCT_KEY = "v0"

      MONTHLY_UNIT_PRICE = ::Billing::Money.new(49 * 100)

      # Returns nothing.
      def perform
        return unless GitHub.billing_enabled?
        log "Sync - GitHub Advanced Security"
        GitHub.zuorest_client.timeout = 60

        if existing_advanced_security_product_uuid?
          log "Product UUID already exists for `GitHub Advanced Security`"
        else
          create_advanced_security_product unless dry_run?
        end
      end

      private

      def create_advanced_security_product
        ::Billing::ZuoraProduct.create(
          product_type: PRODUCT_TYPE,
          product_key: PRODUCT_KEY,
          product_name: "GitHub Advanced Security",
          charges: [
            type: :unit,
            unit: "Seats",
            prices: { User::BillingDependency::MONTHLY_PLAN.to_sym => MONTHLY_UNIT_PRICE.dollars }
          ],
          billing_frequencies: User::BillingDependency::MONTHLY_PLAN
        )
      rescue Zuorest::HttpError => e
        log "Error when attempting to sync GitHub Advanced Security to Zuora, see details:"
        log e.inspect
        log e.data
      ensure
        msg  = existing_advanced_security_product_uuid? ? "was successful" : "failed"
        log "Sync for `GitHub Advanced Security` #{msg}"
      end

      def existing_advanced_security_product_uuid?
        scope = ::Billing::ProductUUID.where(product_type: PRODUCT_TYPE, product_key: PRODUCT_KEY)
        scope.where(billing_cycle: User::BillingDependency::MONTHLY_PLAN).exists?
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

    opts.on("--no-rollback", "Do not write a rollback file; this may speed up your transition or dry run.") do
      options[:no_rollback] = true
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::CreateGitHubAdvancedSecurityInZuora.new(**options)
  transition.run
end
