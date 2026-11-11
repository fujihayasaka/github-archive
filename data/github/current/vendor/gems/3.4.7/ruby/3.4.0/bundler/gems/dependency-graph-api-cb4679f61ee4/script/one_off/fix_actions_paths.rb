#!/usr/bin/env ruby
#                                __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# One-off script to update actions workflow paths that incorrectly end with a forward slash in their path
#
# Usage: script/one_off/fix_actions_paths.rb [-w]

require "optparse"
require_relative "../../config/environment"

checkpoint = Checkpoint.find_or_create_by(name: "fix_actions_paths")

# Set default options.
options = { write: false }

OptionParser.new do |opts|
  opts.banner = "Usage: fix_actions_paths.rb [--write -w]"
  opts.on("-w", "--write", "Persist changes to the database") do
    options[:write] = true
  end

end.parse!(Array(ARGV))

checkpoint_start = checkpoint.get
updated_manifests_count = 0
deleted_manifests_count = 0

ActiveRecord::Base.connected_to(role: :analytics) do
  puts "Starting actions path fix in #{options[:write] ? "write" : "no-op"} mode..."
  paths_to_fix = Manifest.where(package_manager: Types::PackageManager[:actions], path: ".github/workflows/")
  paths_to_fix.find_in_batches(batch_size: 100) do |batch|
    batch.each do |manifest|
          correct_path_exists =  Manifest.exists?(package_manager: Types::PackageManager[:actions], path: ".github/workflows", filename: manifest.filename, repository_id: manifest.repository_id)

      if correct_path_exists
        # delete manifest with incorrect path
        puts "#{options[:write] ? 'deleting' : 'would delete'} #{manifest.filename} - duplicate with incorrect path"

        ActiveRecord::Base.connected_to(role: :writing) { manifest.destroy } if options[:write]

        deleted_manifests_count += 1
      else
        # update manifest with correct path
        puts "#{options[:write] ? 'updating' : 'would update'} #{manifest.filename} - has incorrect path"

        ActiveRecord::Base.connected_to(role: :writing) { manifest.update(path: ".github/workflows") } if options[:write]

        updated_manifests_count += 1
      end

            ActiveRecord::Base.connected_to(role: :writing) { checkpoint.update(last_checkpointed_id: checkpoint_start + updated_manifests_count + deleted_manifests_count) } if options[:write]
    end
  end

  puts "Done! In #{options[:write] ? "write" : "no-op"} mode."
  puts "#{updated_manifests_count} manifests updated.\n#{deleted_manifests_count} manifests deleted.\n#{updated_manifests_count + deleted_manifests_count} manifests total."
end
