#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Backfill insights organisations
# Usage: script/one_off/backfill_dependency_insights
require "optparse"
require_relative "../../config/environment"

options = {}
OptionParser.new do |opts|
  opts.on("-w", "--write", "Run backfill script in write mode") do
    options[:write] = true
  end
  opts.on("-p", "--package_manager=PACKAGE_MANAGER",  "Scope backfill to ecosystem") do |pm|
    options[:package_manager] = pm
  end
  opts.on("-s", "--start_at=START_AT", Integer, "Starting point") do |start_at|
    options[:start_at] = start_at
  end
end.parse!

def backfill_dependency_insights(options:)
  checkpoint = Checkpoint.find_or_create_by(name: "backfill_dependency_insights")
  throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)

  package_manager = options[:package_manager]
  start_at = options[:start_at] || checkpoint.last_checkpointed_id
  count = 0

  DependencyGraph.logger.info("starting backfill from checkpoint",
    "gh.dryrun" => !options[:write],
    "gh.dependency_graph.backfill.checkpoint_value" => start_at,
  )

  throttler.throttle(:"dependency-graph") do
    DependencyInsightsBackfill.find_each(start: start_at) do |org|
      begin
        if package_manager
          next unless Repository.joins(:manifests)
                        .where(
                          dg_repositories: { github_owner_id: org.github_owner_id },
                          dg_manifests: { package_manager: Types::PackageManager.coerce(package_manager) })
                        .exists?
        end

        count += 1
        DependencyGraph.logger.info("starting backfill for org",
          "gh.repo.owner_id" => org.github_owner_id
        )

        if options[:write]
          org.backfill
        end

        DependencyGraph.logger.info("done backfilling org",
          "gh.repo.owner_id" => org.github_owner_id
        )
        checkpoint.update(last_checkpointed_id: org.id)
      rescue => e
        DependencyGraph.logger.error("backfilling org failed",
          { "gh.repo.owner_id" => org.github_owner_id },
          e
        )
      end
    end
  end

  puts "Completed backfill. #{count} orgs processed."
end

backfill_dependency_insights(options: options)
