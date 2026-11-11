# frozen_string_literal: true

require_relative "../../../config/environment"
require "slop"
require "dependabot/transition"

#
# Transitions are orchestrated by the GitHub transitions service and are run
# via chatops:
#
#   .transitions run <pr-url> <environment> <arguments>
#
# A pull request is required to run a transition, so the first step is to
# create one for the transition files.
#
# To run a transition in a particular stamp, specify the stamp as the
# <environment>, e.g., prod-weu-01. To run a transition in all stamps,
# specify * as the <environment>.
#
# Before running a transition you should lock dependabot-api deployments.
#
# To run this transition in dry-run mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260410162815_cleanup_orphaned_active_storage_records.rb -v
#
# To run this transition in write mode, issue the following chatop in the
# #dependabot-ops channel:
#
#   .transitions run <pr-url> <environment> 20260410162815_cleanup_orphaned_active_storage_records.rb -v -w
#
# Once the transition is complete, merge the pull request.
#
module Dependabot
  module Transitions
    class CleanupOrphanedActiveStorageRecords < Dependabot::Transition
      # Transitions provide an alternative to running arbitrary code in
      # production without code review.
      #
      # When designing a transition, favor an approach that can be run in small
      # batches and ensure your script is idempotent and safe to resume/re-run.
      #
      # Database connections default to writing, so be sure to test dry runs
      # thoroughly.

      # Number of attachment records to delete at a time
      BATCH_SIZE = 100

      # Returns nothing.
      def perform # rubocop:disable Metrics/MethodLength
        total_processed = 0
        record_types.each do |record_type|
          log "Processing attachments for #{record_type}..."

          record_type_processed = 0
          relation = missing_attachment_relation(record_type.constantize)

          offset_id = 0
          while offset_id <= max_id
            range = (offset_id...(offset_id + 1_000_000))
            ids = relation.where(id: range).limit(BATCH_SIZE).pluck(:id)
            if ids.empty?
              # if there are no ids in the current range, move to the next range
              offset_id += 1_000_000
              next
            end

            process(ids, record_type)
            record_type_processed += ids.count
            # Move the offset_id to the last processed id + 1
            # and iterate.
            offset_id = ids.last + 1
          end

          log "Finished processing #{record_type_processed} #{record_type} attachments."
          total_processed += record_type_processed
        end

        # Log a final summary of the transition run.
        if dry_run?
          log "DRY RUN complete. Total orphaned attachments found: #{total_processed}"
        else
          log "Cleanup complete. Total orphaned attachments deleted: #{total_processed}"
        end
      end

      def process(batch, record_type)
        attempt = 0

        if dry_run?
          batch_count = batch.count
          log <<~LOG.squish
            #{record_type}: Found #{batch_count} orphaned attachments between #{batch.first} and #{batch.last}
          LOG
          return batch_count
        end

        # Each batch is wrapped in a freno throttle to back off when
        # replication lag is elevated, and in a transaction for atomicity.
        deleted_count = Dependabot.freno_throttler.throttle(Freno::DEPENDABOT_CLUSTER) do
          ActiveStorage::Attachment.transaction do
            ActiveStorage::Attachment.where(id: batch).delete_all_with_dependents
          end
        end

        log "#{record_type}: Deleted #{deleted_count} orphaned attachments between #{batch.first} and #{batch.last}"
      rescue Freno::Throttler::Error, *Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES => e
        log "#{record_type}: Error between #{batch.first} and #{batch.last}. #{e.detailed_message}"
        raise if attempt >= 3

        attempt += 1
        sleep(2**attempt)
        retry
      end

      private

      def record_types
        @record_types ||= ActiveRecord::Base.connected_to(role: :reading) do
          ActiveStorage::Attachment.distinct.pluck(:record_type)
        end
      end

      def max_id
        @max_id ||= ActiveRecord::Base.connected_to(role: :reading) do
          ActiveStorage::Attachment.maximum(:id).to_i
        end
      end

      def missing_attachment_relation(attached_to_class)
        class_name = attached_to_class.name
        table_name = attached_to_class.table_name
        ActiveStorage::Attachment.
          where(record_type: class_name).
          joins("LEFT JOIN #{table_name} ON #{ActiveStorage::Attachment.table_name}.record_id = #{table_name}.id").
          where(table_name => { id: nil }).
          order(:id)
      end
    end
  end
end

# Run as a single process if this script is run directly
if $PROGRAM_NAME == __FILE__
  slop = Slop.parse(help: true, strict: true, validate_types: true) do |options|
    options.bool "-w",
                 "--write",
                 "Enable writes - this defaults to false for safety.",
                 default: false

    options.bool "-v",
                 "--verbose",
                 "Log verbose output"
  end

  options = slop.to_hash
  options = options.merge(dry_run: !options[:write])

  transition = Dependabot::Transitions::CleanupOrphanedActiveStorageRecords.new(**options)
  transition.run
end
