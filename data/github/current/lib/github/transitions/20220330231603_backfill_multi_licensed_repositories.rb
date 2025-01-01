# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
require "divvy"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220330231603_backfill_multi_licensed_repositories.rb --verbose | tee -a /tmp/backfill_multi_licensed_repositories.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220330231603_backfill_multi_licensed_repositories.rb --verbose -w | tee -a /tmp/backfill_multi_licensed_repositories.log
#
module GitHub
  module Transitions
    class BackfillMultiLicensedRepositories < Transition
      # Uncomment this if running this transition with Divvy
      include Divvy::Parallelizable

      # It is recommended to add an ActiveRecord subclass (if applicable) to your transition for each table you need
      # inside the transition itself. You can then also copy all the code within those subclasses that the transition
      # needs into the subclass defined in the transition.
      #
      # This way the transition is self-contained and no change outside of it has any influence.
      #
      # ```
      # class ClassName < ApplicationRecord::Domain::DomainName
      #   self.table_name = :class_name
      #
      #   # Add any relevant attributes or class methods to the class inside the transition
      # end
      # ```

      LICENSE_ID_OTHER = License::IDS_TO_LICENSES.key("other")
      BATCH_SIZE = GitHub.enterprise? ? 10000 : 100
      UPDATE_BATCH_SIZE = GitHub.enterprise? ? 1000 : 1
      attr_reader :iterator

      def after_initialize
        min_id = @other_args[:start_id] || readonly do
          ApplicationRecord::Domain::Repositories.github_sql
            .value("SELECT COALESCE(MIN(id), 0) FROM repository_licenses")
        end
        max_id = @other_args[:end_id] || readonly do
          ApplicationRecord::Domain::Repositories.github_sql
            .value("SELECT COALESCE(MAX(id), 0) FROM repository_licenses")
        end
        batch_size = @other_args[:batch_size] || BATCH_SIZE
        @iterator = readonly do
          ApplicationRecord::Domain::Repositories
            .github_sql_batched_between(start: min_id, finish: max_id, batch_size: batch_size)
        end
        @iterator.add <<-SQL
          -- id must go first for batched between to work properly
          SELECT id, repository_id FROM repository_licenses
          WHERE id BETWEEN :start AND :last
          AND filepath IS NULL
        SQL
      end

      def perform
        dispatch { |rows| process(rows) }
      end

      def dispatch
        iterator.batches.each do |rows|
          yield rows
        end
      end

      def process(rows)
        old_licenses = rows.map { |row| row[0] }
        repository_ids = rows.map { |row| row[1] }
        repositories = Repository.where(id: repository_ids)
        new_rows = []
        repositories.each do |repository|
          detected_licenses = repository.rpc.detect_licenses(repository.default_oid)[:licenses]
          detected_licenses.each do |detected_license|
            new_rows << { repository_id: repository.id, license_id: License.find_by_key(detected_license[:license_key]).id, filepath: detected_license[:filepath] }
          end
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          RepositoryLicense.transaction do
            old_licenses.each_slice(UPDATE_BATCH_SIZE) do |slice|
              RepositoryLicense.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
                log "Deleting old licenses for: #{slice}" if verbose?
                run_batch_delete slice unless dry_run?
              end
            end
            new_rows.each_slice(UPDATE_BATCH_SIZE) do |slice|
              RepositoryLicense.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
                log "Creating license for repos: #{slice.map { |item| item[:repository_id] }}" if verbose?
                run_batch_create slice unless dry_run?
              end
            end
          end
        end
      end

      private

      def run_batch_create(rows)
        sql = ApplicationRecord::Domain::Repositories.github_sql.new "INSERT INTO repository_licenses (repository_id, license_id, filepath) VALUES #{rows.map { |row| "(#{row[:repository_id]}, #{row[:license_id]}, '#{row[:filepath]}')" }.join(", ")}"
        sql.run
        sql.affected_rows
      end

      def run_batch_delete(rows)
        query = "DELETE FROM repository_licenses WHERE id IN (#{rows.join(", ")})"
        sql = ApplicationRecord::Domain::Repositories.github_sql.new query
        sql.run
        sql.affected_rows
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

  options[:workers] ||= 1
  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  # transition = GitHub::Transitions::BackfillMultiLicensedRepositories.new(**options)
  # transition.run

  # If choosing to use Divvy and run this transition as a multithreaded process
  # uncomment the below commands to pass the transition to Divvy, as well as an
  # option for worker count:
  transition = GitHub::Transitions::BackfillMultiLicensedRepositories.new(**options)
  divvy = Divvy::Master.new(transition, options[:workers], options[:verbose])
  divvy.run
end
