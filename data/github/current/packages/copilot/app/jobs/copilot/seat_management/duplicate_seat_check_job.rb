# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class DuplicateSeatCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 3.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_organization_deduplicate_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        ) do
          if FeatureFlag.vexi.enabled?(:copilot_optimized_duplicate_seat_check, default: false)
            find_and_enqueue_duplicate_orgs_optimized
          else
            find_and_enqueue_duplicate_orgs_legacy
          end
        end
      end

      private

      BATCH_SIZE = 10_000

      # Number of child jobs to enqueue before adding another SPREAD_SECONDS delay.
      ENQUEUE_BATCH_SIZE = 1_000

      # Seconds of delay added between each slice of enqueued child jobs.
      SPREAD_SECONDS = 1

      # Optimized query that avoids the JOIN by querying copilot_seats directly,
      # which already has organization_id and assigned_user_id columns with indexes.
      # Batches by organization_id ranges to avoid scanning the entire table at once.
      # Child jobs are staggered with progressive delays to avoid flooding the queue.
      sig { void }
      def find_and_enqueue_duplicate_orgs_optimized
        min_id = Copilot::Seat.where.not(organization_id: nil).minimum(:organization_id)
        max_id = Copilot::Seat.where.not(organization_id: nil).maximum(:organization_id)
        if min_id.nil? || max_id.nil?
          GitHub.logger.info("Max or min organization_id is nil, skipping duplicate seat check", "gh.min_id" => min_id, "gh.max_id" => max_id)
          return
        end

        enqueued_count = T.let(0, Integer)
        batch_start = T.let(min_id, Integer)
        while batch_start <= max_id
          batch_end = batch_start + BATCH_SIZE - 1
          GitHub.logger.info("DuplicateSeatCheck Batch", "gh.org_id_range" => "#{batch_start}-#{batch_end}", "gh.enqueued_count" => enqueued_count)

          sql = Arel.sql(<<-SQL)
            SELECT organization_id, SUM(duplicate_count) AS total_duplicates
            FROM (
              SELECT organization_id, count(*) AS duplicate_count
              FROM copilot_seats
              WHERE organization_id BETWEEN #{batch_start} AND #{batch_end}
              GROUP BY organization_id, assigned_user_id
              HAVING count(*) > 1
            ) AS duplicates
            GROUP BY organization_id
          SQL

          Copilot::Seat.connection.select_rows(sql).each do |organization_id, duplicate_count|
            wait_seconds = (enqueued_count / ENQUEUE_BATCH_SIZE) * SPREAD_SECONDS

            GitHub.logger.info("Queueing organization deduplication", "gh.org.id" => organization_id, "gh.copilot.duplicate.count" => duplicate_count, "gh.wait_seconds" => wait_seconds)
            Copilot::SeatManagement::OrganizationDeduplicateJob.set(wait: wait_seconds.seconds).perform_later(organization_id)

            enqueued_count += 1
          end

          batch_start += BATCH_SIZE
        end
      end

      sig { void }
      def find_and_enqueue_duplicate_orgs_legacy
        sql = Arel.sql(<<-SQL)
          SELECT count(*), copilot_seat_assignments.owner_id
          FROM copilot_seat_assignments
          INNER JOIN copilot_seats ON copilot_seat_assignments.id = copilot_seats.copilot_seat_assignment_id
          WHERE copilot_seat_assignments.owner_type = 'Organization'
          GROUP BY copilot_seat_assignments.owner_id, copilot_seats.assigned_user_id
          HAVING (count(*) > 1)
        SQL

        Copilot::SeatAssignment.connection.select_rows(sql).each do |count, organization_id|
          GitHub.logger.info("Queueing organization deduplication", "gh.org.id" => organization_id, "gh.copilot.duplicate.count" => count)
          Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(organization_id)
        end
      end
    end
  end
end
