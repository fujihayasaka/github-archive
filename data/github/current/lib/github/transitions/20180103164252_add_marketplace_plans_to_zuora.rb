# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20180103164252_add_marketplace_plans_to_zuora.rb -v | tee -a /tmp/add_marketplace_plans_to_zuora.log
#
module GitHub
  module Transitions
    class AddMarketplacePlansToZuora < Transition
      attr_reader :iterator, :users_cancelled
      BATCH_SIZE = 100

      def after_initialize
        max_id = readonly { ApplicationRecord::Domain::Integrations.github_sql.value("SELECT COALESCE(max(id),0) FROM marketplace_listing_plans WHERE state IN (#{Marketplace::ListingPlan.state_value(:published)}, #{Marketplace::ListingPlan.state_value(:retired)})") }
        @iterator = ApplicationRecord::Domain::Integrations.github_sql_batched_between start: 0, finish: max_id, batch_size: BATCH_SIZE
        @marketplace_plans_added = 0
      end

      def perform
        return unless GitHub.billing_enabled?
        create_batches
        readonly_batches = GitHub::SQL::Readonly.new(iterator.batches)
        readonly_batches.each do |batch|
          process(batch)
        end

        log "Added #{@marketplace_plans_added} marketplace plans to zuora"
      end

      # Returns nothing.
      def process(plan_ids)
        marketplace_plans = Marketplace::ListingPlan.where(id: plan_ids.flatten)
        marketplace_plans.each do |plan|
          existing_uuids = ::Billing::ProductUUID.where(
            product_type: "marketplace.listing_plan",
            product_key: plan.id,
          )

          unless existing_uuids.count == 2
            log "Adding #{plan.name} to Zuora" if verbose
            plan.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) { plan.sync_to_zuora unless dry_run }
            @marketplace_plans_added += 1
          end
        end
      end

      private

      def create_batches
        @iterator.add <<-SQL
          SELECT id
          FROM marketplace_listing_plans
          WHERE state IN (#{Marketplace::ListingPlan.state_value(:published)}, #{Marketplace::ListingPlan.state_value(:retired)}) AND (id BETWEEN :start AND :last)
        SQL
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby /workspaces/github/lib/github/transitions/20180103164252_add_marketplace_plans_to_zuora.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::AddMarketplacePlansToZuora.new(options)
  transition.run
end
