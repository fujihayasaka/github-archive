#!/usr/bin/env ruby
#
# Script that ingests packages used by github/github's bin/create-dependabot-example-vulnerable-repo.rb script.
# This script is a giant hack for a couple reasons and could be improved:
#   1. ingest_packages has to be listening
#   2. hardcoded list of packages we "know" come from create-dependabot-example-vulnerable-repo

unless defined?(Rails)
  puts "Don't call this script directly, use Rails Runner: `bin/rails r script/dev/import-packages-for-mock-data.rb`"
  exit
end

if Rails.env.production?
  puts "Don't use this script in production!"
  exit
end

puts "This script will do nothing unless ingest_packages is running! Make sure to start it before running this."

OneOffImporters.run!(:rubygems, package_name: "octokit")
OneOffImporters.run!(:rubygems, package_name: "multipart-post")
OneOffImporters.run!(:rubygems, package_name: "faraday")
