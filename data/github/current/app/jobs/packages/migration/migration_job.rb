# typed: false
# frozen_string_literal: true

module Packages
  module Migration
    class MigrationJob < BatchedJob

      attr_accessor :offset_id, :progress, :is_forced, :is_failed_retry, :is_first_run, :last_migrated_package_id, :is_error_retry, :delay_package_migration

      protected

      def log(data)
        GitHub.logger.info(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.registry.job_enqueued_at" => initially_enqueued_at,
          "gh.registry.job_is_forced" => is_forced,
          "gh.registry.job_is_error_retry" => is_error_retry,
          "gh.registry.job_delay_package_migration" => delay_package_migration,
          "gh.registry.job_is_first_run" => is_first_run,
          "gh.registry.job_offset_id" => offset_id,
          "gh.registry.job_progress" => progress,
        )
      end

      private

      def perform(*args, force: false, retry_failed: false, is_error_retry: false, delay_package_migration: nil, last_migrated_package_id: 0, initial_start: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        @is_forced = force
        @is_failed_retry = retry_failed
        @is_error_retry = is_error_retry
        @delay_package_migration = delay_package_migration
        @last_migrated_package_id = last_migrated_package_id
        @offset_id = offset_item_id
        @progress = progress
        @is_first_run = offset_item_id == 0
        super
      end

    end
  end
end
