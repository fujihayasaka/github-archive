# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   $ gudo bin/safe-ruby lib/github/transitions/20171106193137_move_team_subscriptions_into_newsies.rb -v | tee -a /tmp/move_team_subscriptions_into_newsies.log
#
module GitHub
  module Transitions
    class MoveTeamSubscriptionsIntoNewsies < Transition
      DEFAULT_BATCH_SIZE = 50

      attr_reader :batch_size, :start_id, :max_id

      def after_initialize
        @batch_size = @other_args.delete(:batch_size) || DEFAULT_BATCH_SIZE
        @start_id = @other_args.delete(:start_id) || 0
        @max_id = @other_args.delete(:max_id) || readonly do
          Ability.github_sql.new("SELECT COALESCE(max(id),0) FROM abilities /* abilities-select-no-priority-needed */").value
        end

        @iterator = Ability.github_sql_batched_between(start: start_id,
          finish: max_id, batch_size: batch_size)
        @iterator.bind(priorities: [
          Ability.priorities[:direct],
          Ability.priorities[:indirect],
        ])
        @iterator.add <<-SQL
          SELECT id, subject_id, actor_id
          FROM abilities
          WHERE id BETWEEN :start AND :last
            AND priority IN :priorities
            AND actor_type = 'User'
            AND subject_type = 'Team'
        SQL
      end

      def log(str)
        super([@dry_run ? "[dry run]" : "", str].join(" "))
      end

      # Returns nothing.
      def perform
        log "Starting transition #{self.class.to_s.underscore} from id #{start_id}"

        number_of_batches = (max_id.to_f / batch_size.to_f).ceil
        subscriptions_count = 0
        batches_count = 0
        GitHub::SQL::Readonly.new(@iterator.batches).each do |team_and_user_ids|
          batches_count += 1
          percentage_complete = (batches_count.to_f * 100) / number_of_batches.to_f
          status "#{percentage_complete}%% done. Processing #{team_and_user_ids.size} entities in batch #{batches_count} out of #{number_of_batches}" unless Rails.env.test?

          next if team_and_user_ids.empty?

          log "Adding subscriptions for memberships from id #{team_and_user_ids.first[0]} to #{team_and_user_ids.last[0]}: #{team_and_user_ids}" if verbose

          now = GitHub::SQL::NOW
          rows = GitHub::SQL::ROWS(
            team_and_user_ids.map do |team_and_user_id|
              team_id = team_and_user_id[1]
              user_id = team_and_user_id[2]
              [
                "Team",
                team_id,
                user_id,
                now,
              ]
            end,
          )

          if dry_run?
            subscriptions_count += team_and_user_ids.size
          else
            Newsies::ThreadSubscription.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              ActiveRecord::Base.connected_to(role: :writing) do
                sql = Newsies::ThreadSubscription.github_sql.new <<-SQL, rows: rows
                  INSERT IGNORE INTO
                    notification_subscriptions
                    (list_type, list_id, user_id, created_at)
                  VALUES
                    :rows
                SQL

                sql.run
                subscriptions_count += sql.affected_rows
              end
            end
          end
        end

        log "Created #{subscriptions_count} team subscriptions."
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: move_team_subscriptions_into_newsies.rb [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:dry_run] = !write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end

    opts.on("-s", "--start_id ID", Integer, "The start ID to scan the abilities table for team memberships") do |start_id|
      options[:start_id] = start_id
    end

    opts.on("-m", "--max_id ID", Integer, "The max ID to scan the abilities table for team memberships") do |max_id|
      options[:max_id] = max_id
    end

    opts.on("-b", "--batch_size SIZE", Integer, "The batch size to scan the abilities table for team memberships") do |batch_size|
      options[:batch_size] = batch_size
    end
  end.parse!

  options[:dry_run] ||= true

  transition = GitHub::Transitions::MoveTeamSubscriptionsIntoNewsies.new(options)
  transition.run
end
