# typed: true
# frozen_string_literal: true

class ProcessOrganizationMembersExportJob < ApplicationJob
  # Using the critical queue because users are waiting for results
  queue_as :critical

  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  resolve_tenant_context do |export_id|
    export = OrganizationMembersExport.find(export_id)
    if export.subject.is_a?(Business)
      export.subject
    elsif export.subject.is_enterprise_managed?
      export.subject.enterprise_managed_business
    else
      export.subject.business
    end
  end

  def perform(export_id, audit_event = nil)
    export = OrganizationMembersExport.find_by(id: export_id)
    return unless export
    status = JobStatus.find(export.token)
    return unless status

    status.track do
      export.process
    end
  end
end
