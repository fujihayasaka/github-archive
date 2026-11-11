# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# Only applicable to GHES
module GitHub
  module Transitions
    class BackfillGhesRepoDependabotAlertsEnablement < Transition
      BATCH_SIZE = 1000

      ENABLED_KEY = "dependency_vulnerability_alerts.enabled"
      DISABLED_KEY = "dependency_vulnerability_alerts.disabled"
      ANALYSIS_KEY = "ghe_content_analysis"

      CONFIG_ENTRIES_COLUMNS = [
        :target_id,
        :target_type,
        :updater_id,
        :name,
        :value,
        :final,
        :created_at,
        :updated_at,
      ].freeze

      CONFIG_ENTRIES_COLUMN_LITERALS = CONFIG_ENTRIES_COLUMNS.map { |c| GitHub::SQL::LITERAL(c) }

      attr_reader :iterator

      def after_initialize
        return unless GitHub.enterprise?

        @update_time = Time.zone.now

        # The most common, and preferred, approach is to define your iterator
        # here using `BatchedBetween`. Prefer using a min_id with BatchedBetween
        # queries. Not doing so can lead to _very_ slow transition tests (https://github.com/github/github/pull/92565)
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Repositories.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM repositories")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Repositories.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM repositories")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE

        # github_sql_batched_between holds on to the current connection so we need to wrap it in a readonly block
        # when instantiating it so that we read from replicas when we iterate over it.
        @iterator = readonly do
          ApplicationRecord::Domain::Repositories
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id, public, parent_id FROM repositories
          WHERE id BETWEEN :start AND :last AND
          id NOT IN (
            SELECT target_id FROM configuration_entries
            WHERE target_type = 'Repository' AND name = '#{ENABLED_KEY}' AND value = 'true' AND target_id BETWEEN :start AND :last)
          ORDER BY id ASC
        SQL
      end

      def perform
        return unless GitHub.enterprise?

        return unless alerts_enabled_globally?

        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        remove_any_disabled_configs
      end

      private

      def process(rows)
        repo_ids = rows.map do |(id)|
          id
        end

        write_new_repo_configs(repo_ids)

        log_prefix = dry_run? ? "Dry run. Would have " : ""
        log "#{log_prefix} enabled #{repo_ids.size} repos" if verbose?
      end

      def alerts_enabled_globally?
        return false unless GitHub.dependency_graph_enabled? && GitHub.dotcom_connection_enabled?

        # This is equivalent to doing - GitHub.ghe_content_analysis_enabled?
        count = readonly do
          ApplicationRecord::Domain::ConfigurationEntries.github_sql
            .value("SELECT COUNT(*) FROM configuration_entries WHERE name = '#{ANALYSIS_KEY}' AND target_type = 'global' AND target_id = 0")
        end

        count > 0
      end

      # For public, non forked, repos we consider Dependabot Alerts enabled if there isn't a disabled config
      # therefore we need to remove any repository disabled config values
      def remove_any_disabled_configs
        if verbose?
          log_prefix = dry_run? ? "Dry run. " : ""
          log "#{log_prefix}removing all #{DISABLED_KEY} repo configuration_entries records"
        end
        ActiveRecord::Base.connected_to(role: :writing) do
          ApplicationRecord::Domain::ConfigurationEntries.github_sql.run <<-SQL, disabled_key: DISABLED_KEY
            DELETE FROM configuration_entries
            WHERE
            target_type = 'Repository' AND
            name = :disabled_key
          SQL
        end unless dry_run?
      end

      def write_new_repo_configs(repo_ids)
        return if repo_ids.blank?
        ApplicationRecord::Domain::ConfigurationEntries.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          if verbose?
            log_prefix = dry_run? ? "Dry run. Would be " : ""
            readable_repo_ids = repo_ids.each_slice(10).map(&:to_s).join("\n")
            log "#{log_prefix}writing new repo configuration_entries records for #{readable_repo_ids}"
          end
          ActiveRecord::Base.connected_to(role: :writing) do
            config_entries = GitHub::SQL::ROWS(repo_ids.map do |repo_id|
              [
                repo_id,                                    # target_id
                "Repository",                               # target_type
                User.ghost.id,                              # updater_id
                ENABLED_KEY,                                # name
                "true",                                     # value
                0,                                          # final
                @update_time,                               # created_at
                @update_time,                               # updated_at
              ]
            end)
            ApplicationRecord::Domain::ConfigurationEntries.github_sql.run <<-SQL, columns: CONFIG_ENTRIES_COLUMN_LITERALS, values: config_entries
              INSERT INTO configuration_entries :columns
              VALUES :values
            SQL
          end unless dry_run?
        end
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
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::BackfillGhesRepoDependabotAlertsEnablement.new(**options)
  transition.run
end
