# rubocop:todo GitHub/EnforcePackageAppStructure
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

  def self.prefix
    "process-organization-members-export-job"
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

  def perform(export_id, audit_event = nil)
    export = OrganizationMembersExport.find_by(id: export_id)
    return unless export
    status = self.class.status(export.token)
    # Temporary stopgap to make sure we don't break existing exports when this is deployed
    status = EnterpriseAccounts::JobStatus.find(export.token) if status.nil?
    return unless status

    status.track do
      export.process
    end
  end
end
