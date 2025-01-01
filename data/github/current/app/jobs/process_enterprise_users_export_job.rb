# typed: true
# frozen_string_literal: true
require "ghec_admin"

# This job is queued up via GHECAdmin::EnterpriseUsersExport
class ProcessEnterpriseUsersExportJob < ApplicationJob
  # Using the critical queue because users are waiting for results
  queue_as :critical

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  resolve_tenant_context do |export_id|
    export = BusinessReportExport.find(export_id)
    if export.owner.is_a?(Business)
      export.owner
    end
  end

  def perform(export_id)
    export = BusinessReportExport.find_by(id: export_id)
    return unless export
    status = JobStatus.find(export.token)
    return unless status

    status.track do
      GitHub.logger.info("Export starting", "gh.business_report_export.id": export.id)
      use_mysql1_replica do
        GHECAdmin::EnterpriseUsersExport.new(business_report_export: export).process
      end
      GitHub.logger.info("Export finished", "gh.business_report_export.id": export.id)
    end
  end
end
