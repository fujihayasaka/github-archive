# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CodeScanningAssessmentTimeoutJob < ApplicationJob
    queue_as :code_scanning_assessment_timeout
    retry_on_dirty_exit

    schedule interval: 15.minutes
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      # Update each record individually to preserve after_commit callbacks
      # (refresh_assessment_status and instrument_status_updated).
      # This may trigger redundant refresh_status! calls when multiple repos
      # belong to the same assessment, but refresh_status! is idempotent and
      # the set is bounded by MAX_REPOSITORIES_PER_ASSESSMENT (20).
      CodeScanningAssessmentRepository.stale.in_batches do |batch|
        batch.find_each do |repo_record|
          ActiveRecord::Base.connected_to(role: :writing) do
            repo_record.update!(status: :timed_out)
          end
        end
      end
    end
  end
end
