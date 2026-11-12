#!/usr/bin/env ruby
#                                __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# One-off script to find and possibly delete package releases that map to deleted NPM packages
# Also generate list of affected orgs in dependency insights
#
# Usage: script/one_off/find_dangling_npm_package_releases.rb [-w]

require_relative "../../config/environment"
require "optparse"

options = { delete: false }
OptionParser.new do |opts|
  opts.on("-w", "--write", "Deletes dangling npm package releases and their corresponding associations") do
    options[:delete] = true
  end
end.parse!(Array(ARGV))

def find_dangling_npm_package_releases(options)
  package_releases_to_delete = []
  affected_orgs = []

  ActiveRecord::Base.connected_to(role: :reading) do
    PackageRelease.where(package_manager: 2).in_batches do |releases|
      releases.each do |release|
        release_id = release.id

        puts "Processing release with id: #{release_id}"

        # If package release has no associated package add it to releases to delete
        unless Package.exists?(release.package_id)
          package_releases_to_delete << release_id

          puts "Package release with id: #{release_id}, name: #{release.package_name}, package_manager: #{release.package_manager} has no corresponding package"

          # Finds orgs in dependency insights that depended on that package release
          orgs_with_package_release = Views::PackageReleaseDependentCount.where(package_release_id: release_id)

          orgs_with_package_release.each do |org_dependent|
            affected_orgs << org_dependent.github_owner_id
            puts "Org with owner_id #{org_dependent.github_owner_id} depends on package release with id: #{release_id} to be deleted"
          end

          # Delete the package release from db, this will also delete org insights entry for org
          if options[:delete]
            ActiveRecord::Base.connected_to(role: :writing) do
              puts "Deleting package release: #{release.package_name}, package_manager: #{release.package_manager}"
              release.destroy
            end
          end
        end
      end
    end

    # Duplicate org ids may be present so remove duplicates
    affected_orgs = affected_orgs.uniq
    puts "Affected_org's owner ids: #{affected_orgs}"

    File.open("dep_insights_affected_orgs.txt", "w") { |f| f.write affected_orgs.join("\n") }

    if options[:delete]
      puts "#{package_releases_to_delete.size} package releases were deleted, #{affected_orgs.size} org dependent entries for release were affected"
    else
      puts "#{package_releases_to_delete.size} package releases would have been deleted, #{affected_orgs.size} org dependent entries for release would have been affected"
    end
  end
end

find_dangling_npm_package_releases(options)
