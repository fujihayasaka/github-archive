#!/usr/bin/env ruby
#                                __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# One-off script to set `unpublished_at` to nil in cases when it's set to 0.
#
# Usage: script/one_off/unpublished_at_0_fix.rb [-w]

require "optparse"
require_relative "../../config/environment"

# Set default options.
options = { write: false }
# Parse options and set the flags.
OptionParser.new do |opts|
  opts.banner = "Usage: unpublished_at_0_fix.rb [--write -w]"
  opts.on("-w", "--write", "Persist changes to the database") do
    options[:write] = true
  end

  opts.on("--package-manager=MANAGER", "Package Manager") do |package_manager|
    options[:package_manager] = package_manager.to_i
  end
end.parse!(Array(ARGV))

error = "Invalid package manager '#{options[:package_manager]}'" unless options[:package_manager].in?(Types::PackageManager.collect(&:id))
error = "Missing package manager!" unless options[:package_manager].present?
if error
  puts <<~EOS
  #{error} Try again with the --package-manager=MANAGER option!
  Valid arguments: #{Types::PackageManager.collect { |pm| "#{pm.id} (#{pm.human_name})" }.join(", ")}
  EOS
  exit
end

OUTPUT_FILENAME = "unpublished-at-to-nil-#{options[:package_manager]}-#{Time.now.to_i}.csv"

all_the_ids = []

ActiveRecord::Base.connected_to(role: :reading) do
  package_releases = PackageRelease.select(:id).joins(:package).where(
    dg_packages: { package_manager: options[:package_manager] },
    dg_package_versions: { unpublished_at: Time.at(0) }
  )
  package_releases.in_batches do |releases|
    puts "Loaded batch..." # This is here because K8s gets upset if you don't keep writing to STDOUT
    all_the_ids << releases.collect(&:id)

    # Only update the record if we wanna write.
    if options[:write]
      ActiveRecord::Base.connected_to(role: :writing) do
        puts "Updating batch..." # This is here because K8s gets upset if you don't keep writing to STDOUT
        releases.update_all(unpublished_at: nil)
        puts "Updated batch!" # This is here because K8s gets upset if you don't keep writing to STDOUT
      end
    end

    sleep(1) # Give it a rest for a second.
  end
end

unless all_the_ids.present?
  puts "I didn't do anything because there were #{all_the_ids.count} results to fix! That's technically a good thing!"
  exit
end

if options[:write]
  puts "Set #{all_the_ids.count} records unpublished_at to nil!"
else
  puts "I would have set #{all_the_ids.count} records unpublished_at to nil, but this was a dry run!"
end

File.write(OUTPUT_FILENAME, all_the_ids.join(","))
puts "Output the affected IDs to #{OUTPUT_FILENAME}"
