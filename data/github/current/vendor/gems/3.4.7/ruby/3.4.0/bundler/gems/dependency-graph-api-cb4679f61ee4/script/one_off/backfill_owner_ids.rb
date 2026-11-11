#!/usr/bin/env ruby
#                                __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# One-off script to set missing `owner_id` values in `dg_repositories`.
#
# Usage: script/one_off/backfill_owner_ids.rb [-w]

require "optparse"
require_relative "../../config/environment"

# Set default options.
options = { write: false }
# Parse options and set the flags.
OptionParser.new do |opts|
  opts.banner = "Usage: backfill_owner_ids.rb [--write -w]"
  opts.on("-w", "--write", "Persist changes to the database") do
    options[:write] = true
  end
end.parse!(Array(ARGV))

throttler = Freno::Throttler.new(client: Freno.client, app: :dependency_graph)

update_count = 0

ActiveRecord::Base.connected_to(role: :reading) do
  Repository.where(github_owner_id: 0).in_batches(of: 100) do |repos|
    puts "Loaded batch..." # This is here because K8s gets upset if you don't keep writing to STDOUT

    repo_ids = repos.map(&:github_repository_id)

    # Create a map of repo ids to owner ids
    # Use writing connection since reading connection does not exist for github
    owner_id_by_repo_id = ActiveRecord::Base.connected_to(role: :writing) do
      GitHub::Repository.where(id: repo_ids).pluck(:id, :owner_id).to_h
    end

    puts "Updating batch..." # This is here because K8s gets upset if you don't keep writing to STDOUT
    throttler.throttle(:"dependency-graph") do
      repos.each do |repo|
        owner_id = owner_id_by_repo_id[repo.github_repository_id]
        if owner_id
          # Only update the record if we wanna write.
          if options[:write]
            ActiveRecord::Base.connected_to(role: :writing) do
              repo.update_attributes(github_owner_id: owner_id)
            end
          end
          update_count += 1
        else
          puts "Missing owner id for repository #{repo.github_repository_id}"
        end
      end
    end
    puts "Updated batch!" # This is here because K8s gets upset if you don't keep writing to STDOUT
  end
end

puts "#{options[:write] ? "Updated" : "Would have updated"} #{update_count} repositories"
