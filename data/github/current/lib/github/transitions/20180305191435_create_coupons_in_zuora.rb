# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20180305191435_create_coupons_in_zuora.rb -v | tee -a /tmp/create_coupons_in_zuora.log
#
module GitHub
  module Transitions
    class CreateCouponsInZuora < Transition
      def perform
        return unless GitHub.billing_enabled?
        log "Synching - GitHub Coupons"
        sync_coupons unless dry_run?
      end

      def sync_coupons
        begin
          percentage_coupon&.sync_to_zuora
          fixed_amount_coupon&.sync_to_zuora
        rescue Zuorest::HttpError => e
          log "Error when attempting to sync Coupons to Zuora, see details:"
          log e.inspect
          log e.data
        end

        msg = existing_coupons? ? "was successful" : "failed"
        log "Sync for Coupons #{msg}"
      end

      private

      def percentage_coupon
        Coupon.new(discount: 0.1)
      end

      def fixed_amount_coupon
        Coupon.new(discount: 5)
      end

      def existing_coupons?
        percentage_coupon.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN) && fixed_amount_coupon.zuora_id(cycle: User::BillingDependency::YEARLY_PLAN)
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby /workspaces/github/lib/github/transitions/20180305191435_create_coupons_in_zuora.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateCouponsInZuora.new(options)
  transition.run
end
