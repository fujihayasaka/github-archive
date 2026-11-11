# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CodeScanningAssessmentDataRetentionJob < ApplicationJob
    RETENTION_PERIOD = T.let(1.year, ActiveSupport::Duration)
    BATCH_SIZE = 100

    queue_as :code_scanning_assessment_data_retention
    retry_on_dirty_exit

    schedule interval: 1.day
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      # The most recent assessment per org is always preserved, even if older
      # than the retention period, so every org keeps at least one record.
      latest_per_org_sql = CodeScanningAssessment
        .group(:owner_id)
        .select(:owner_id, "MAX(number) AS number")
        .to_sql

      CodeScanningAssessment
        .where("created_at < ?", RETENTION_PERIOD.ago)
        .where(
          "(code_scanning_assessments.owner_id, code_scanning_assessments.number) NOT IN (#{latest_per_org_sql})"
        )
        .in_batches(of: BATCH_SIZE, cursor: [:created_at, :id]) do |batch|
          ActiveRecord::Base.connected_to(role: :writing) do
            batch.destroy_all
          end
        end
    end
  end
end
