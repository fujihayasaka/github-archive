#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Audit repos and delete the ones that don't exist anymore!
# Usage: script/one_off/backfill_manifest_dependency_orgs.rb [-w]

require "optparse"
require_relative "../../config/environment"

options = { write: false, org_id: nil }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Actually write package_manager and exact_version columns to db") do
    options[:write] = true
  end
  opts.on("-o", "--org-id [ORG_ID]", OptionParser::DecimalInteger, "Only backfill the organization id specified") do |org_id|
    options[:org_id] = org_id
  end
end.parse!

def backfill_manifest_dependencies(write:, org_id:)
  puts "starting backfill in #{write ? 'write' : 'safe'} mode!"
  puts "only backfilling organization: #{org_id}" if org_id
  begin
    updated_count = 0
    query = ManifestDependency.joins(manifest: :repository)
    query = query.merge(Repository.where(github_owner_id: org_id)) if org_id
    ActiveRecord::Base.connected_to(role: :reading) do
      query.in_batches.each_with_index do |batch, number|
        puts "processing batch #{number + 1}"
        if write
          ActiveRecord::Base.connected_to(role: :writing) do
            updated_count += batch.update_all("#{ManifestDependency.table_name}.package_manager = #{Manifest.table_name}.package_manager, #{ManifestDependency.table_name}.exact_version = CASE WHEN #{ManifestDependency.table_name}.requirements LIKE '= %' THEN REPLACE(#{ManifestDependency.table_name}.requirements, '= ', '') ELSE NULL END")
          end
        else
          updated_count += batch.count
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
