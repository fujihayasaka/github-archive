# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "ghec_admin"

# This job is queued up via GHECAdmin::EnterpriseDormantUsersExport
class ProcessDormantUsersExportJob < ApplicationJob
  # This is on the lowworker worker pool

  queue_as :ghec_admin_reports

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  resolve_tenant_context do |export_id|
    export = BusinessReportExport.find(export_id)
    if export.owner.is_a?(Business)
      export.owner
    end
  end

  def self.prefix
    "process-dormant-users-export-job"
  end

  def self.job_id(export_token)
    "#{prefix}_#{export_token}"
  end

  def self.status(export_token)
    EnterpriseAccounts::JobStatus.find(job_id(export_token))
  end

  def self.create_status(export_token)
    EnterpriseAccounts::JobStatus.create(id: job_id(export_token))
  end

  def perform(export_id)
    export = BusinessReportExport.find_by(id: export_id)
    return unless export
    status = self.class.status(export.token)
    # Temporary stopgap to make sure we don't break existing exports when this is deployed
    status = EnterpriseAccounts::JobStatus.find(export.token) if status.nil?
    return unless status

    status.track do
      GitHub.logger.info("Export starting", "gh.business_report_export.id": export.id)

      GHECAdmin::EnterpriseDormantUsersExport.new(business_report_export: export).process

      GitHub.logger.info("Export finished", "gh.business_report_export.id": export.id)
    end
  end
end
