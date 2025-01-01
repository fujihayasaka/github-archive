# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# This is a transition that will be used to notify admins of orgs and enterprises whose users will be enrolled in an upcoming cohort for requiring 2FA.
# It uses the datawarehouse (GitHub.presto) to run queries for returning admin user IDs.
# The query results are processed in batches of 100 users by default (overridable with the --yielded_batch_size option).
# By default, the presto queries are limited by a total count that can be returned in a single query. The discovery lib handles querying until all are returned.
#
# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
#
# Dry run chatops example: .transitions run <PR> production lib/github/transitions/20230607161808_notify_admins_for_two_factor_requirement_rollout.rb --verbose --reason=published_app --cohort=2
module GitHub
  module Transitions
    class NotifyAdminsForTwoFactorRequirementRollout < Transition
      DEFAULT_YIELDED_BATCH_SIZE = 100
      MAX_THROTTLE_RETRIES = 5
      DEFAULT_AFFECTED_USER_THRESHOLD = 50

      def after_initialize
        @reason = TwoFactorRequirement::Reason.from_symbol(@other_args[:reason].to_sym)
        @affected_user_threshold = @other_args[:affected_user_threshold] || DEFAULT_AFFECTED_USER_THRESHOLD
        @yielded_batch_size = @other_args[:yielded_batch_size] || DEFAULT_YIELDED_BATCH_SIZE

        @total_admins_notified = 0
      end

      def perform
        transition_start_time = Time.now.utc
        query = TwoFactorRequirement::Queries.find(reason: @reason)
        unless query
          log "No query found for reason '#{@reason}'."
          return
        end

        log "Running presto query for admin notification for reason '#{@reason}'" + \
        "#{" with affected_user_threshold limit set to '#{@affected_user_threshold}'" if @affected_user_threshold}" + \
          ". Results will be processed in batches of #{@yielded_batch_size}..."

        total_discovered = query.run_business_admin_query(
          yielded_batch_size: @yielded_batch_size,
          affected_user_threshold: @affected_user_threshold,
        ) do |query_rows, requirement_reason|
          process_start_time = Time.now.utc
          process_batch(query_rows, requirement_reason)
          time_elapsed = GitHub::Dogstats.duration(process_start_time, Time.now.utc)
          log "Processing batch took #{time_elapsed} milliseconds.\n"
          GitHub.dogstats.distribution("transitions.notify_admins_for_two_factor_requirement_rollout.processing_during", time_elapsed)
        end

        if total_discovered >= TwoFactorRequirement::Queries::PRESTO_QUERY_RESULTS_LIMIT
          log "Warning: Total admins discovered (#{total_discovered}) reached or exceeded the presto query results limit (#{TwoFactorRequirement::Queries::PRESTO_QUERY_RESULTS_LIMIT})."
        else
          log "Total admins discovered: #{total_discovered}"
        end

        log "Total admins notified: #{@total_admins_notified}"

        time_elapsed = GitHub::Dogstats.duration(transition_start_time, Time.now.utc)
        log "Transition took #{time_elapsed} milliseconds.\n"
        GitHub.dogstats.distribution("transitions.notify_admins_for_two_factor_requirement_rollout.overall_duration", time_elapsed)
      end

      # Process a batch of query results from the presto query.
      # query_rows - An array of rows from the notification query in the format: admin_user_id (int), entity_id (int), entity_name (string), is_org (boolean), user_count (int), user_2fa_enabled_count (int)
      # requirement_reason - The reason for the 2FA requirement (see TwoFactorRequirement::Reason::REASONS)
      def process_batch(query_rows, requirement_reason)
        if dry_run?
          log "Would process batch of size #{query_rows.size} business/org admins for #{requirement_reason}."
        else
          batch_start_time = Time.now.utc
          log "Processing batch of size #{query_rows.size} business/org admins for #{requirement_reason}."

          with_throttle do
            user_ids = query_rows.map { |result| result[0] }
            users = User.where(id: user_ids)

            if users.count < user_ids.count
              missing_ids = user_ids - users.pluck(:id)
              log "Missing users for ids: #{missing_ids}"
            end

            query_rows.each do |row|
              user_id = row[0]
              user = users.find { |u| u.id == user_id }
              entity_name = row[2]
              is_org = row[3]
              user_count = row[4]
              user_2fa_enabled_count = row[5]
              AccountMailer.two_factor_requirement_inform_admin(user, entity_name, is_org, user_count, user_2fa_enabled_count).deliver_later
            end

            @total_admins_notified += users.count
            log "Notified #{users.count} admins."
          end

          time_elapsed = GitHub::Dogstats.duration(batch_start_time, Time.now.utc)
          log "Batch took #{time_elapsed} milliseconds.\n"
          GitHub.dogstats.distribution("transitions.notify_admins_for_two_factor_requirement_rollout.batch_duration", time_elapsed)
        end
      end

      def with_throttle
        ActiveRecord::Base.connected_to(role: :reading) do
          User.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            yield
          end
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

    opts.on("--reason REASON", "The two factor requirement reason (see TwoFactorRequirement::Reason::REASONS) that belongs to the query you wish to run.") do |reason|
      options[:reason] = reason
    end

    opts.on("--affected_user_threshold THRESHOLD", Integer, "The minimum number of users affected by the requirement for admins to be notified") do |threshold|
      options[:affected_user_threshold] = threshold
    end

    opts.on("--yielded_batch_size SIZE", Integer, "Number of rows to process at a time") do |size|
      options[:yielded_batch_size] = size
    end
  end.parse!

  options[:dry_run] = !options[:write]

  transition = GitHub::Transitions::NotifyAdminsForTwoFactorRequirementRollout.new(**options)
  transition.run

  transition = GitHub::Transitions::NotifyAdminsForTwoFactorRequirementRollout.new(**options)
  transition.run
end
