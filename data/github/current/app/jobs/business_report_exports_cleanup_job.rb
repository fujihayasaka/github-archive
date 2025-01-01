# typed: true
# frozen_string_literal: true

class BusinessReportExportsCleanupJob < ApplicationJob
  schedule interval: 1.day, condition: -> { !GitHub.single_business_environment? }
  queue_as :business_report_exports_cleanup

  retry_on_dirty_exit

  BATCH_SIZE = 1000
  UPDATED = 3.days

  # Public - scheduled job to remove old business reports
  def perform
    self.class.reports_to_be_deleted.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |report|
        begin
          with_write { report.destroy }
        rescue GHECAdmin::StorageError => e
          Failbot.report(e, report_id: report.id, report_owner_type: report.owner_type, report_owner_id: report.owner_id, token: report.token, type: report.report_type)
        end
      end
    end
  end

  def self.reports_to_be_deleted
    BusinessReportExport.where(["completed_at < ?", UPDATED.ago])
  end
end
