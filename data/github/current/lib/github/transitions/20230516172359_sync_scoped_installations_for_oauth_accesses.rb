# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class SyncScopedInstallationsForOauthAccesses < Transition
      # include Divvy::Parallelizable

      READ_BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      WRITE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 10

      attr_reader :iterator
      attr_reader :total_updated

      def read_batch_size
        @other_args[:read_batch_size] || READ_BATCH_SIZE
      end

      def write_batch_size
        @other_args[:write_batch_size] || WRITE_BATCH_SIZE
      end

      def after_initialize
        @total_updated = 0

        min_id = @other_args[:start_id] || readonly do
          OauthAccess.connection.select_value(Arel.sql("SELECT COALESCE(MIN(id), 0) FROM oauth_accesses"))
        end

        max_id = @other_args[:end_id] || readonly do
          OauthAccess.connection.select_value(Arel.sql("SELECT COALESCE(MAX(id), 0) FROM oauth_accesses"))
        end

        @iterator = readonly do
          OauthAccess.github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end

        @iterator.add <<-SQL
            SELECT id, installation_id FROM oauth_accesses
            WHERE id BETWEEN :start AND :last
            AND  installation_type  = "ScopedIntegrationInstallation"
        SQL
      end

      # Returns nothing.
      def perform
        # We are preserving this transition for historical reasons,
        # but it no longer performs any work.
        log("This transition no longer performs any work. It is now a no-op.")

        # GitHub::SQL::Readonly.new(iterator.batches).each do |rows|
        #   process(rows)
        # end

        # verb = dry_run? ? "Would have updated" : "Updated"
        # log("#{verb} #{total_updated} records")
      end

      private

      # rows = [[id, installation_id],[id, installation_id], etc.]
      def process(rows)
        rows.each_slice(write_batch_size) do |slice|
          log "doing something with scoped installation id #{slice.last}" if verbose?

          ids = slice.map(&:last)
          children = ScopedIntegrationInstallation.includes(:parent).where(id: ids)

          children.each do |child|
            parent = child.parent
            next if parent.nil? || parent.version.nil?

            Permission.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
              run_update(parent, child)
            end
          end
        end
      end

      def run_update(parent, child)
        parent_version = parent.version
        child_version = IntegrationVersion.new(default_permissions: permissions_for(child))
        diff = parent_version.diff(child_version)

        if diff.permissions_downgraded? || diff.permissions_removed?
          @total_updated += 1
        end

        return if dry_run?

        # code borrowed from app/jobs/sync_scoped_integration_installations_job.rb
        if diff.permissions_downgraded?
          downgraded_permissions = diff.permissions_downgraded.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(resource, access), out|
            out[access] << resource
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            downgraded_permissions.each_pair do |access, resources|
              Permissions::Service.update_action_for_permissions(
                actor_ids: [child.id],
                actor_type: "ScopedIntegrationInstallation",
                subject_types: subject_types_from(resources),
                action: access,
                entry_point: :sync_scoped_installations_for_oauth_accesses_transition_downgrade
              )
            end
          end
        end

        # code borrowed from app/jobs/sync_scoped_integration_installations_job.rb
        if diff.permissions_removed?
          removed_subject_types = subject_types_from(diff.permissions_removed)

          ActiveRecord::Base.connected_to(role: :writing) do
            Permissions::Service.revoke_permissions_granted_on_actors(
              actor_ids: [child.id],
              actor_type: "ScopedIntegrationInstallation",
              subject_types: removed_subject_types,
              entry_point: :sync_scoped_installations_for_oauth_accesses_transition_revoke
            )
          end
        end
      end

      def subject_types_from(resources)
        if resources.is_a?(Array)
          Repository::Resources.all_prefixed_subject_types(resources) + \
            Organization::Resources.all_prefixed_subject_types(resources)
        elsif resources.is_a?(Hash)
          subject_types_from(resources.keys)
        end
      end

      def permissions_for(scoped_installation)
        permissions = Permission.where(
          actor_id: scoped_installation.ability_id,
          actor_type: scoped_installation.ability_type
        ).select(:subject_type, :action).distinct

        permissions.each_with_object({}) do |permission, memo|
          resource = permission.subject_type.split("/").last
          memo[resource] = permission.action.to_sym
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

    opts.on("--start_id ID", Integer, "ID to start processing") do |id|
      options[:start_id] = id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |id|
      options[:end_id] = id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |size|
      options[:read_batch_size] = size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |size|
      options[:write_batch_size] = size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |count|
      options[:workers] = count
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::SyncScopedInstallationsForOauthAccesses.new(**options)
  transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  # transition = GitHub::Transitions::SyncScopedInstallationsForOauthAccesses.new(**options)
  # divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  # divvy.run
end
