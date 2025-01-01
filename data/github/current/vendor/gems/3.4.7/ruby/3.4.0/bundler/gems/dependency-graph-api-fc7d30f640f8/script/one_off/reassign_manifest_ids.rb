#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Reassigns manifests to new manifest type ids
# Usage: script/one_off/reassign_manifest_ids.rb

require_relative "../../config/environment"

def reassign_manifest_id(manifest_name, old_type_id, new_type_id)
  manifests_reassigned = 0

  manifest_ids_to_reassign = ActiveRecord::Base.connected_to(role: :reading) do
    Manifest.where(filename: manifest_name).where(manifest_type: old_type_id).pluck(:id)
  end

  puts "generated ids of #{manifest_name} manifests to update"

  ActiveRecord::Base.connected_to(role: :writing) do
    Manifest.where(id: manifest_ids_to_reassign).in_batches(of: 500).each do |batch|
      puts "processing new batch of #{manifest_name} manifests"
      batch.update_all(manifest_type: new_type_id)

      manifests_reassigned += batch.size
    end
  end

  puts "#{manifests_reassigned} #{manifest_name} manifests have been reassigned to id: #{new_type_id}"
end

# As articualted in issue: https://github.com/github/dependency-graph-api/issues/1296
# We need to reassign manifest ids for composer.json and jquery manifests to resolve duplicate manifest type declarations
reassign_manifest_id("jquery.min.js", 15, 17)
reassign_manifest_id("jquery-3.3.1.min.js", 15, 17)
reassign_manifest_id("composer.json", 14, 16)
