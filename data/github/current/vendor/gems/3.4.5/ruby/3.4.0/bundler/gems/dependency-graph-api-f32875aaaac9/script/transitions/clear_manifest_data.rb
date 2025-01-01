#!/usr/bin/env ruby

require_relative "../../lib/transitions/clear_manifest_data"

# Delete manifests and dependencies associated with go.sum files as per https://github.com/github/dependency-graph/issues/655
# Dotcom usage: run in #dg-ops .transitions run <PR url> <environment> clear_gosum_data.rb [-r]

options = { dry_run: false, filters: {} }
OptionParser.new do |opts|
  opts.on("-f", "--filename go.sum,go.mod", Array, "A CSV list of filenames to filter for") do |csv|
    options[:filters][:filename] = csv.length == 1 ? csv.first : csv
  end
  opts.on("-p", "--package-manager rubygems", String, "A string to coerce into a supported PackageManager type to filter for") do |pm|
    options[:filters][:package_manager] = Types::PackageManager.coerce(pm)
  end
  opts.on("-d", "--dry-run", "Run script without deleting go.sum manifests") do
    options[:dry_run] = true
  end
  opts.on("-m", "--manifests 100", Integer, "Manifests per batch to fetch for deletion") do |m|
    options[:manifest_batch_size] = m
  end
  opts.on("-d", "--dependencies 1000", Integer, "Dependencies per batch to fetch and delete") do |d|
    options[:dependency_batch_size] = d
  end
  opts.on("-r", "--retries 10", Integer, "Max retry attempts on recoverable errors/timeouts") do |r|
    options[:max_attempts] = r
  end
end.parse!

Transitions::ClearManifestData.new(options).execute
