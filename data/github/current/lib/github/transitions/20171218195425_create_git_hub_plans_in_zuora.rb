# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20171218195425_create_git_hub_plans_in_zuora.rb -v | tee -a /tmp/create_git_hub_plans_in_zuora.log
#
module GitHub
  module Transitions
    class CreateGitHubPlansInZuora < Transition
      BATCH_SIZE = 100

      def perform
        return unless GitHub.billing_enabled?
        GitHub::Plan.all.select(&:paid?).each do |plan|
          ::Billing::ProductUUID.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "Syncing - GitHub #{plan} Plan"
            sync_plan(plan) unless dry_run?
          end
        end
      end

      def sync_plan(plan)
        if existing_uuid?(plan)
          log "ProductUUIDs found for `GitHub #{plan} Plan`"
        else
          create_product(plan)
        end
      end

      def create_product(plan)
        begin
          plan.sync_to_zuora
        rescue Zuorest::HttpError => e
          log "Error when attempting to sync GitHub #{plan} Plan to Zuora, see details:"
          log e.inspect
          log e.data
        end

        msg = existing_uuid?(plan) ? "was successful" : "failed"
        log "Sync for `GitHub #{plan} Plan` #{msg}"
      end

      def existing_uuid?(plan)
        plan.product_uuid(User::BillingDependency::MONTHLY_PLAN) && plan.product_uuid(User::BillingDependency::YEARLY_PLAN)
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby /workspaces/github/lib/github/transitions/20171218195425_create_git_hub_plans_in_zuora.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::CreateGitHubPlansInZuora.new(options)
  transition.run
end
