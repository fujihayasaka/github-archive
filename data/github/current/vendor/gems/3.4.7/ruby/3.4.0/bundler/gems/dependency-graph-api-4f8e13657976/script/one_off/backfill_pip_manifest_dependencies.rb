#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Redetect pip manifests with unnormalized dependencies
# Usage: script/one_off/backfill_pip_manifest_dependencies.rb [-w]

require "optparse"
require_relative "../../config/environment"

options = { write: false }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Update package_name") do
    options[:write] = true
  end
end.parse!

def update_package_name(dep)
  name = ManifestAdapters::Pip::DependencyString.normalize_package_name(dep.package_name)
  if dep.package_name != name
    dep.update_columns(package_name: name)
  end
rescue ActiveRecord::RecordNotUnique
  puts "(dup key err) #{dep.class.name} with id #{dep.id} normalised to #{dep.package_name} which already exists for the manifest."
  dep.delete
end

def backfill_pip_manifest_dependencies(write:)
  puts "starting backfill in #{write ? 'write' : 'safe'} mode!"
  begin
    checkpoint = Checkpoint.find_or_create_by(name: "backfill_pip_manifest_dependencies")
    last_processed_id = checkpoint.last_checkpointed_id || 0

    pip = Types::PackageManager[:pip]
    throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)
    updated_count = 0

    ActiveRecord::Base.connected_to(role: :reading) do
      Manifest.for_package_manager(pip).in_batches(of: 100, start: last_processed_id).each_with_index do |batch, number|
        puts "processing batch #{number + 1}"

        manifest_dependencies_to_update = ManifestDependency.where(manifest: batch).where("package_name REGEXP ?", "[_.]+|[-]{2,}")
        updated_count += manifest_dependencies_to_update.count

        if write
          ActiveRecord::Base.connected_to(role: :writing) do
            throttler.throttle(:"dependency-graph") do
              manifest_dependencies_to_update.find_each do |dep|
                abstract_dep = AbstractRepositoryDependency.for_package_manager(pip).where(package_name: dep.package_name)
                                .from(AbstractRepositoryDependency.quoted_table_name)
                                .first
                update_package_name(abstract_dep) if abstract_dep
                update_package_name(dep)
              end
              Checkpoint.where(name: checkpoint.name).update(last_checkpointed_id: batch.last.id)
            end
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

Instrument.time("dg.backfill_pip_manifest_dependencies") do
  backfill_pip_manifest_dependencies(options)
end
