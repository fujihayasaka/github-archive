#!/usr/bin/env ruby

require_relative "../../lib/transitions/destroy_orphaned_manifests"

# Destroy orphaned manifests as per https://github.com/github/dependency-graph/issues/7173
# Transition usage: run in #dg-ops .transitions run <PR url> <environment> destroy_orphaned_manifests.rb [--options]

options = {
  batch_size: 100,
  dry_run: true,
}

enable_console_appender = false
enable_query_logging = false

OptionParser.new do |opts|
  opts.on("--batch-size N", Integer, "Set the number of manifests to destroy at a time") do |bs|
    options[:batch_size] = bs
  end

  # Example: --data-directory script/transitions/orphaned-manifests-data
  opts.on("--data-directory DIR", String, "Set the directory containing the CSV file with orphaned manifest IDs") do |dir|
    options[:data_directory] = dir
  end

  # Example: --csv-name batch_1.csv
  opts.on("--csv-name NAME", String, "Set the name of the CSV file containing orphaned manifest IDs") do |name|
    options[:csv_name] = name
  end

  opts.on("--write", "Perform the deletion") do
    options[:dry_run] = false
  end

  opts.on("--stdout", "Enable console appender") do
    enable_console_appender = true
  end

  opts.on("--log-sql", "Enable query logging") do
    enable_query_logging = true
  end
end.parse!

if enable_console_appender
  SemanticLogger.add_appender(io: $stdout) unless SemanticLogger.appenders.console_output?
end

if enable_query_logging
  # Special case: if we are in development then print the raw SQL queries.
  # This is a little nicer to read than the tagged log output.
  if Rails.env.development?
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      puts "#{sql}\n" unless sql.blank?
    end
  else
    # In production/any other environment, log the SQL queries as structured data, as normal.
    RailsSemanticLogger::ActiveRecord::LogSubscriber.logger.level = :debug
  end
end

# Only the CSV name is required, the data directory defaults to "script/transitions/orphaned-manifests-data"
raise OptionParser::MissingArgument, "--csv-name is required" if options[:csv_name].nil?

# Execute the transition to destroy orphaned manifests
Transitions::DestroyOrphanedManifests.new(**options).execute
