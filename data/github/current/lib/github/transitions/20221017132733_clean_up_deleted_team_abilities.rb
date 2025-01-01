# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221017132733_clean_up_deleted_team_abilities.rb --verbose | tee -a /tmp/clean_up_deleted_team_abilities_dry_run.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20221017132733_clean_up_deleted_team_abilities.rb --verbose -w | tee -a /tmp/clean_up_deleted_team_abilities_write_run.log
module GitHub
  module Transitions
    class CleanUpDeletedTeamAbilities < Transition
      BATCH_SIZE = 1_000
      DELETE_BATCH_SIZE = 100

      attr_reader :iterator
      attr_reader :total_deleted
      attr_reader :deleted_team_ids

      def after_initialize
        @total_deleted = 0
        @deleted_team_ids = []
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::IamAbilities.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM abilities")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::IamAbilities.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM abilities")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE
        readonly do
          @iterator = ApplicationRecord::Domain::IamAbilities
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        end
        @iterator.add <<-SQL
          SELECT id, subject_type, subject_id, actor_type, actor_id
          FROM abilities
          WHERE id BETWEEN :start AND :last
          AND (subject_type = 'Team' OR actor_type = 'Team')
        SQL
      end

      def perform
        GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
          process(rows)
        end

        if verbose?
          unique_deleted_team_ids = deleted_team_ids.uniq.compact
          if dry_run?
            log "Would have deleted #{total_deleted} abilities for #{unique_deleted_team_ids.size} deleted teams with the following IDs: #{unique_deleted_team_ids}"
          else
            log "Deleted #{total_deleted} abilities for #{unique_deleted_team_ids.size} deleted teams with the following IDs: #{unique_deleted_team_ids}"
          end
        end
      end

      private

      def process(rows)
        team_ids = rows.map do |item|
          if item[1] == "Team" # Team as subject
            item[2]
          elsif item[3] == "Team" # Team as actor
            item[4]
          end
        end
        return unless team_ids
        team_ids.uniq!
        team_ids.compact!
        return if team_ids.empty?

        existing_team_ids = readonly do
          Team.github_sql.values <<-SQL, ids: team_ids
            SELECT id
            FROM teams
            WHERE id IN :ids
          SQL
        end
        non_existent_team_ids = team_ids - existing_team_ids.flatten
        return if non_existent_team_ids.empty?
        @deleted_team_ids.push(*non_existent_team_ids)

        abilities_ids_to_delete = readonly do
          Ability.github_sql.values <<-SQL, non_existent_team_ids: non_existent_team_ids
            SELECT id
            FROM abilities
            WHERE (subject_type = 'Team' AND subject_id IN :non_existent_team_ids)
            OR (actor_type = 'Team' AND actor_id IN :non_existent_team_ids)
          SQL
        end
        return if abilities_ids_to_delete.empty?

        abilities_ids_to_delete.each_slice(DELETE_BATCH_SIZE) do |slice|
          Ability.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            if verbose?
              if dry_run?
                log "Would be deleting abilities with IDs (plus children abilities): #{slice}"
              else
                log "Deleting abilities with IDs (plus children abilities): #{slice}"
              end
            end

            @total_deleted += bulk_delete_abilities(slice)
          end
        end
      end

      def bulk_delete_abilities(abilities_ids)
        return 0 if abilities_ids.empty?

        children_affected_rows = 0
        parent_affected_rows = 0
        children_ids = readonly do
          Ability.github_sql.values <<-SQL, parent_ids: abilities_ids
            SELECT id
            FROM abilities
            WHERE parent_id IN :parent_ids
          SQL
        end

        if dry_run?
          return children_ids.size + abilities_ids.size
        end

        # Delete any children abilities first, then the parent abilities
        children_affected_rows = delete_abilities(children_ids) if children_ids.any?
        parent_affected_rows = delete_abilities(abilities_ids)

        children_affected_rows + parent_affected_rows
      end

      def delete_abilities(ids)
        return 0 if ids.empty?

        deleted = 0

        ids.each_slice(DELETE_BATCH_SIZE) do |slice|
          ActiveRecord::Base.connected_to(role: :writing) do
            sql = ApplicationRecord::Domain::IamAbilities.github_sql.new
            sql.add <<~SQL, ids: slice
              DELETE FROM abilities WHERE id IN :ids
            SQL
            sql.run
            deleted += sql.affected_rows
          end
        end

        deleted
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

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::CleanUpDeletedTeamAbilities.new(**options)
  transition.run
end
