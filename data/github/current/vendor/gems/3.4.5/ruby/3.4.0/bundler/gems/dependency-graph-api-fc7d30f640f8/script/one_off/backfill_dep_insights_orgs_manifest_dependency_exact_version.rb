#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Correct the exact versions of all manifest dependencies of dependency insights orgs
# Usage: script/one_off/backfill_dep_insights_orgs_manifest_dependency_exact_version.rb [-w]

require "optparse"
require_relative "../../config/environment"

options = { write: false }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Actually write package_manager and exact_version columns to db") do
    options[:write] = true
  end
end.parse!

def backfill_manifest_dependencies(write:)
  puts "starting backfill in #{write ? 'write' : 'safe'} mode!"
  begin
    updated_count = 0

    ActiveRecord::Base.connected_to(role: :reading) do
      business_plus_org_ids = DependencyInsightsBackfill.pluck(:github_owner_id)

      business_plus_org_ids.each do |org_id|
        query = ManifestDependency.joins(manifest: :repository).merge(Repository.where(github_owner_id: org_id))
        query.in_batches.each_with_index do |batch, number|
          puts "processing batch #{number + 1}"
          if write
            ActiveRecord::Base.connected_to(role: :writing) do
              updated_count += batch.update_all("#{ManifestDependency.table_name}.exact_version = CASE WHEN #{ManifestDependency.table_name}.requirements LIKE '= %' THEN REPLACE(#{ManifestDependency.table_name}.requirements, '= ', '') ELSE NULL END")
            end
          else
            updated_count += batch.count
          end
        end
      end
    end
    puts "done backfilling! #{updated_count} manifest dependencies #{write ? 'updated' : 'would be updated'}."
  rescue => e
    puts "Exception!"
    Failbot.report(e)
    raise e
  end
end

Instrument.time("dg.backfill_manifest_dependencies") do
  backfill_manifest_dependencies(options)
end
