#!/usr/bin/env ruby
#                                __  __
#   ___  _ __   ___        ___  / _|/ _|
#  / _ \| '_ \ / _ \_____ / _ \| |_| |_
# | (_) | | | |  __/_____| (_) |  _|  _|
#  \___/|_| |_|\___|      \___/|_| |_|
#
# One-off script to find PyPi packages missing from our database.
#
# Usage: script/one_off/find_missing_pypi_packages.rb

require_relative "../../config/environment"

PYPI_SIMPLE_URL = "https://pypi.org/simple/"
OUTPUT_FILENAME = "missing-pypi-packages-#{Time.now.to_i}.txt"

# Fetch the list of PyPi packages from the Simple API
simple_html = Net::HTTP.get(URI(PYPI_SIMPLE_URL))
# Parse the HTML with Nokogiri
simple_document = Nokogiri::HTML(simple_html)
# Collect an array of package names from inside the <a> tags - be sure to downcase so we avoid case sensitivity issues.
packages = simple_document.xpath("//a/text()").collect { |link| link.text.downcase }

puts "Found a total of #{packages.length} from PyPi"

missing = []
ActiveRecord::Base.connected_to(role: :analytics) do
  # In batches of 100, try to find the packages in the DB...
  packages.each_slice(100) do |packages|
    print "." # This is here because K8s gets upset if you don't keep writing to STDOUT

    packages_in_db = Package.where(package_manager: Types::PackageManager[:pip], name: packages).pluck(:name)

    # If a package name we weren't expecting isn't in the Array from the DB, we can consider it missing.
    # Be sure to downcase the packages from the DB so we can avoid case sensitivity issues.
    missing << packages - packages_in_db.collect(&:downcase)
  end
end
print "\n" # Output a newline so our puts below aren't on the same as our "." output.

# Flatten the missing package names so we can get an accurate count.
missing.flatten!

puts "Found #{missing.count} missing packages which are missing from our database"
File.write(OUTPUT_FILENAME, missing.join("\n"))
puts "Output the affected IDs to #{OUTPUT_FILENAME}"
