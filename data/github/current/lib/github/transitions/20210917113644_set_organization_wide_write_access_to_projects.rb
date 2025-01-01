# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20210917113644_set_organization_wide_write_access_to_projects.rb --verbose | tee -a /tmp/set_organization_wide_write_access_to_projects.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20210917113644_set_organization_wide_write_access_to_projects.rb --verbose -w | tee -a /tmp/set_organization_wide_write_access_to_projects.log
#
module GitHub
  module Transitions
    class SetOrganizationWideWriteAccessToProjects < Transition
      def perform
        now = GitHub::SQL::NOW

        log "updating global organization wide access for projects" if verbose?
        return if dry_run?

        results = readonly do
          sql = ApplicationRecord::Domain::ConfigurationEntries.github_sql.new <<-SQL
            SELECT value
            FROM configuration_entries
            WHERE name = 'memex_project_organization_wide_role'
            AND target_type = 'global'
            AND target_id = 0
          SQL
          sql.results
        end

        # Do nothing if there's an existing entry
        return if results.any?

        Configuration::Entry.github_sql.run(<<-SQL, { timestamp: now })
            INSERT INTO configuration_entries
              (target_type, target_id, updater_id, name, value, created_at, updated_at)
            VALUES
              ("global", 0, 0, "memex_project_organization_wide_role", "project_writer", :timestamp, :timestamp)
          SQL
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:batch_size] = size
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::SetOrganizationWideWriteAccessToProjects.new(**options)
  transition.run
end
