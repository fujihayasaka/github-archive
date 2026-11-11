#!/usr/bin/env ruby
#                               __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# Rebuilds the Views::PackageReleaseDependentCount one org at a time
# Usage: script/one_off/rebuild_package_release_dependent_counts_for_dep_insights.rb

require_relative "../../config/environment"

puts "Starting process to clear and rebuild package release dependents for business plus orgs..."

ActiveRecord::Base.connected_to(role: :reading) do
  DependencyInsightsBackfill.where.not(last_backfilled_at: nil).each_with_index do |org, index|
    begin
      puts "processing org: #{index} with org id: #{org.github_owner_id}"

      org_dependents = Views::PackageReleaseDependentCount.where(github_owner_id: org.github_owner_id)

      next if org_dependents.empty?

      ActiveRecord::Base.connected_to(role: :writing) do
        org_dependents.destroy_all

        Views::PackageReleaseDependentCount.rebuild_for(org.github_owner_id)
        puts "Rebuilt Package Release Dependent Counts for org: #{org.github_owner_id}"
      end
    rescue => e
      puts "Exception: #{e.message}, org_id: #{org.github_owner_id}"
      Failbot.report(e, script: "rebuild_package_release_dependent_counts_for_dep_insights", org_id: org.github_owner_id)
      next
    end
  end
end
