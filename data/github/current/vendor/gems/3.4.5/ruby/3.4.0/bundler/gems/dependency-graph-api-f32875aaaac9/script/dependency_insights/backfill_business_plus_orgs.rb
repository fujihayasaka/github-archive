#!/usr/bin/env ruby
#
# Find orgs that are business plus and add them to our backfill table
# Usage: script/dependency_insights/backfill_business_plus_orgs.rb

require_relative "../../config/environment"

throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)

def add_orgs_to_queue(throttler)
  begin
    added_count = 0
    GitHub::User.where({ plan: "business_plus", type: "Organization" }).select(:id).in_batches.each_with_index do |batch, number|
      DependencyGraph.logger.info("starting batch", "gh.batch.number" => number + 1)
      business_plus_ids = batch.collect(&:id)

      next if  business_plus_ids.empty?

      #remove org ids that are already in our database
      already_queued_ids = DependencyInsightsBackfill.where(github_owner_id: business_plus_ids).pluck(:github_owner_id)
      business_plus_ids = business_plus_ids - already_queued_ids

      DependencyGraph.logger.info("found new business plus orgs to add to the database")
      group_counter = 1
      business_plus_ids.in_groups_of(50, false) do |group|
        throttler.throttle(:"dependency-graph") do
          DependencyGraph.logger.info("adding sub-group of batch to backfill table",
            "gh.batch.number" => number + 1,
            "gh.batch.sub_group_number" => group_counter,
          )
          new_rows = group.map { |owner_id| { github_owner_id: owner_id, source: "cronjob" } }
          DependencyInsightsBackfill.create(new_rows)
          group_counter += 1
        rescue ActiveRecord::RecordNotUnique => e
          DependencyGraph.logger.info("skipping creating new backfill for a github_owner_id because one already exists",
            "exception.message" => e.message,
            "gh.repo.owner_id" => owner_id,
          )
        end
      end

      # backfill all the newly found business_plus_ids
      DependencyInsightsBackfill.where(github_owner_id: business_plus_ids).each do |org|
        begin
          throttler.throttle(:"dependency-graph") do
            org.backfill
          end
        rescue => e
          DependencyGraph.logger.error("exception in backfill-business-plus-orgs", e)
          Failbot.report(e)
          next
        end
      end

      DependencyGraph.logger.info("Backfilled orgs", "gh.repo.owner_ids" => business_plus_ids)
      added_count += business_plus_ids.count
    end
    DependencyGraph.logger.info("done looking through orgs", "gh.batch.total" => added_count)
  rescue => e
    DependencyGraph.logger.error("exception while backfilling business plus orgs", e)
    Failbot.report(e)
    raise e
  end
end

def backfill_outstanding_orgs(throttler)
  DependencyGraph.logger.info("about to backfill outstanding orgs that have not been backfilled before")
  backfilled_orgs = 0

  DependencyInsightsBackfill.where(last_backfilled_at: nil).each do |org|
    begin
      throttler.throttle(:"dependency-graph") do
        org.backfill
      end
      backfilled_orgs += 1
    rescue => e
      DependencyGraph.logger.error("exception in backfill-business-plus-orgs", e)
      Failbot.report(e)
      next
    end
  end

  DependencyGraph.logger.info("backfilled outstanding orgs", "gh.batch.total" => backfilled_orgs)
end

Instrument.time("queue_business_plus") do
  add_orgs_to_queue(throttler)
  backfill_outstanding_orgs(throttler)
end
