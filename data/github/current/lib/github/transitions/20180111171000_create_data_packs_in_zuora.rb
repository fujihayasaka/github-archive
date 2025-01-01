# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20180111171000_create_data_packs_in_zuora.rb -v | tee -a /tmp/create_data_packs_in_zuora.log
#
module GitHub
  module Transitions
    class CreateDataPacksInZuora < Transition
      def perform
        return unless GitHub.billing_enabled?
        log "Syncing - GitHub LFS"
        sync_plan unless dry_run?
      end

      def sync_plan
        if existing_lfs?
          log "Monthly and Yearly ProductUUIDs found for `GitHub LFS`"
        else
          create_product
        end
      end

      def create_product
        begin
          ::Asset::Status.sync_to_zuora
        rescue Zuorest::HttpError => e
          log "Error when attempting to sync GitHub LFS to Zuora, see details:"
          log e.inspect
          log e.data
        end

        msg = existing_lfs? ? "was successful" : "failed"
        log "Sync for `GitHub LFS` #{msg}"
      end

      def existing_lfs?
        ::Asset::Status.product_uuid(User::BillingDependency::MONTHLY_PLAN) &&
          ::Asset::Status.product_uuid(User::BillingDependency::YEARLY_PLAN)
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby /workspaces/github/lib/github/transitions/20180111171000_create_data_packs_in_zuora.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateDataPacksInZuora.new(options)
  transition.run
end
