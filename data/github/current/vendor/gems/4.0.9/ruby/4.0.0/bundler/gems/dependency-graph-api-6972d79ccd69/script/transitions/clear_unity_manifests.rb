#!/usr/bin/env ruby

# Clear unity manifests ingested as npm

# Usage:
#### in shell: script/transitions/clear_unity_manifests.rb [-w]
#### with transition: .transitions run <PR url> <environment> clear_unity_manifests.rb [-w]

require "optparse"
require_relative "../../config/environment"

options = { delete: false }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Clear unity manifests") do
    options[:delete] = true
  end
end.parse!


def clear_unity_manifests(options:)
  DependencyGraph.logger.info("starting unity manifests audit!",
    "gh.dryrun" => !options[:delete],
  )
  begin
    checkpoint = Checkpoint.find_or_create_by(name: "clear_unity_manifests")
    last_processed_id = checkpoint.last_checkpointed_id || 0

    npm = Types::PackageManager[:npm]
    throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)
    deleted_count = 0

    ActiveRecord::Base.connected_to(role: :analytics) do

      # The equivalent query for ManifestEntry would be something like:
      #
      # ManifestEntry.joins(manifest_package_version: :manifest_package)
      #   .where("#{ManifestPackage.table_name}.package_manager = ?", npm)
      #   .where("#{ManifestPackage.table_name}.package_name LIKE ?", "com.unity.%")
      #   .select(:manifest_id, :id)
      #   .in_batches(of: 1000, start: last_processed_id)
      #   .each_with_index do |batch, number| ... end
      #
      # It is not implemented like this here since this transition exists to fix a bug
      # that occurred before the creation of the ManifestEntry table.

      ManifestDependency.where(["package_name LIKE ?", "com.unity.%"]).where(package_manager: npm).select(:manifest_id, :id).in_batches(of: 1000, start: last_processed_id).each_with_index do |batch, number|
        DependencyGraph.logger.info("processing batch",
          "gh.batch.number" => number + 1,
        )
        to_delete = batch.pluck(:manifest_id).uniq
        last_id = batch.last.id

        if options[:delete]
          ActiveRecord::Base.connected_to(role: :writing) do
            throttler.throttle(:"dependency-graph") do
              Manifest.where(id: to_delete).destroy_all
              checkpoint.update(last_checkpointed_id: last_id)
            end
          end
        end
        DependencyGraph.logger.info(
          "gh.dependency_graph.transition.action" => "#{options[:delete] ? 'Deleted' : 'Identified'}",
          "gh.dependency_graph.manifest.ids" => to_delete,
        )
        deleted_count += to_delete.count
      end
    end
    DependencyGraph.logger.info("Completed!",
      "gh.dryrun" => !options[:delete],
      "gh.batch.total" => deleted_count,
    )
  rescue => e
    puts "Exception!"
    Failbot.report(e)
    raise e
  end
end

clear_unity_manifests(options: options)
