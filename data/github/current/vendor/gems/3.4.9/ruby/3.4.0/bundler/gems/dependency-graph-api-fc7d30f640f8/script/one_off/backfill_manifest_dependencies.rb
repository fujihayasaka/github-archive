#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Audit repos and delete the ones that don't exist anymore!
# Usage: script/one_off/backfill_manifest_dependencies.rb [-w]

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
    # Create checkpoint of last processed manifest
    checkpoint = Checkpoint.find_or_create_by(name: "backfill_manifest_dependencies_package_manager_exact_version")

    throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)
    last_processed_id = checkpoint.last_checkpointed_id || 0
    updated_count = 0

    ActiveRecord::Base.connected_to(role: :reading) do
      Manifest.in_batches(of: 100, start: last_processed_id).each_with_index do |batch, number|
        puts "processing batch #{number + 1}"
        batch.each do |manifest|
          if write
            ActiveRecord::Base.connected_to(role: :writing) do
              throttler.throttle(:"dependency-graph") do
                package_manager = manifest.package_manager.to_i
                manifest_dependencies_to_update = manifest.dependencies.where(package_manager: nil, exact_version: nil)
                updated_count += manifest_dependencies_to_update.count
                manifest_dependencies_to_update.in_batches(of: 100).update_all("#{ManifestDependency.table_name}.package_manager = #{package_manager}, #{ManifestDependency.table_name}.exact_version = CASE WHEN #{ManifestDependency.table_name}.requirements LIKE '= %' THEN REPLACE(#{ManifestDependency.table_name}.requirements, '= ', '') ELSE NULL END")

                # Update the manifest checkpoint once manifest dependencies have been updated
                Checkpoint.where(name: checkpoint.name).update(last_checkpointed_id: manifest.id)
              end
            end
          else
            updated_count += manifest.dependencies.where(package_manager: nil, exact_version: nil).count
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
