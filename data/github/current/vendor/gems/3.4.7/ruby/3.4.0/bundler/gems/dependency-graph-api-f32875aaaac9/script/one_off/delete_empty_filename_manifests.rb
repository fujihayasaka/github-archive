#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Delete manifests with empty filenames as per https://github.com/github/dependency-graph/issues/1142
# Usage: script/one_off/delete_empty_filename_manifests.rb

require_relative "../../config/environment"

def delete_empty_filename_manifests
  manifest_ids_to_delete = ActiveRecord::Base.connected_to(role: :reading) do
    # Being extra-careful with the conditions here. The investigation of https://github.com/github/dependency-graph/issues/1142
    # showed that all manifests with empty filename were created during a backfill job on 2017-09-01. Should there be manifests
    # with empty filenames created on another day we'd need to take another look at the cause.
    Manifest.where(filename: "").where("id <= 3419").where(created_at: Date.parse("2017-09-01").all_day).pluck(:id)
  end

  puts "#{manifest_ids_to_delete.length} manifest to delete"

  ActiveRecord::Base.connected_to(role: :writing) do
    Manifest.where(id: manifest_ids_to_delete).destroy_all
  end

  puts "#{manifest_ids_to_delete.length} manifests have been deleted"
end

# Addresses https://github.com/github/dependency-graph/issues/1142
delete_empty_filename_manifests
