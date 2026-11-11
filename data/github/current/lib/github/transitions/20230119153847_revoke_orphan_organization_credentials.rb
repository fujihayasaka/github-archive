# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class RevokeOrphanOrganizationCredentials < Transition
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
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Users.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM organization_credential_authorizations")
        end

        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Users.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM organization_credential_authorizations")
        end

        @total_updated = 0

        @iterator = readonly do
          ApplicationRecord::Domain::Users
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: read_batch_size)
        end

        @iterator.add <<-SQL
          SELECT id, organization_id FROM organization_credential_authorizations
          WHERE id BETWEEN :start AND :last
          ORDER BY id
        SQL
      end

      def perform
        # credential_and_organization_ids is an array of the form [[credential_id, organization_id], ...]
        GitHub::SQL::Readonly.new(iterator.batches).each do |credential_and_organization_ids|
          org_ids = credential_and_organization_ids.map(&:last)
          existing_org_ids = Organization.where(id: org_ids).pluck(:id)
          # identify the orgs that have been deleted
          deleted_org_ids = org_ids - existing_org_ids
          next if deleted_org_ids.empty?
          orphan_credential_ids = credential_and_organization_ids.select do |ids|
            deleted_org_ids.include?(ids.last)
          end.map(&:first)

          process(orphan_credential_ids)
        end

        # To include a final summary of the changes made:
        verb = dry_run? ? "Would have updated" : "Updated"
        log("#{verb} #{total_updated} records")
      end

      private

      def process(credential_ids)
        credential_ids.each_slice(write_batch_size) do |slice|
          Organization::CredentialAuthorization.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log "Removing Organization::CredentialAuthorization: #{slice.map { |item| item[0] }}" if verbose?
            # preload the org just to run the org presence safety check below
            credentials = Organization::CredentialAuthorization.where(id: slice).preload(:organization)
            @total_updated += credentials.count
            run_batch_update(credentials)
          end
        end
      end

      def run_batch_update(credentials)
        return if dry_run?

        ActiveRecord::Base.connected_to(role: :writing) do
          credentials.each do |credential|
            if credential.organization.present?
              # this should never happen!
              error_message = "Attempted to remove non orphaned credential: #{credential.id}"
              log(error_message)
              raise RuntimeError.new(error_message)
            end

            credential.destroy
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
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do |write|
      options[:write] = write
    end

    opts.on("-v", "--verbose", "Log verbose output") do |verbose|
      options[:verbose] = verbose
    end

    opts.on("--start_id ID", Integer, "ID to start processing") do |start_id|
      options[:start_id] = start_id
    end

    opts.on("--end_id ID", Integer, "ID to end processing") do |end_id|
      options[:end_id] = end_id
    end

    opts.on("--read_batch_size SIZE", Integer, "Number of rows to read at a time") do |read_batch_size|
      options[:read_batch_size] = read_batch_size
    end

    opts.on("--write_batch_size SIZE", Integer, "Number of rows to write at a time") do |write_batch_size|
      options[:write_batch_size] = write_batch_size
    end

    opts.on("-n", "--workers COUNT", Integer, "Worker count") do |workers|
      options[:workers] = workers
    end
  end.parse!

  options[:dry_run] = !options[:write]
  options[:workers] ||= 1

  transition = GitHub::Transitions::RevokeOrphanOrganizationCredentials.new(**options)
  transition.run
end
