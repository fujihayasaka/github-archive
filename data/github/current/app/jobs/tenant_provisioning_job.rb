# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TenantProvisioningJob < ApplicationJob
  queue_as :tenant_provisioning

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(multi_tenant_provisioning_request_id)
    return if GitHub.single_or_multi_tenant_enterprise?
    mtpr = MultiTenantProvisioningRequest.find_by(id: multi_tenant_provisioning_request_id)
    return unless mtpr&.valid?
    return unless mtpr.pending?

    # this is the slow step, takes 10+ seconds
    mtpr.provision_tenant

    if mtpr.provisioning_step == "in_progress"
      with_write { mtpr.save! }
    else
      subdomain_taken = mtpr.errors[:subdomain]&.include?("is already taken") || false

      with_write { mtpr.destroy! }

      EnterpriseManagedUserMailer.tenant_creation_error(
        mtpr.subdomain,
        mtpr.admin_work_email,
        mtpr.data_hosting_region,
        subdomain_taken
      ).deliver_later

      GitHub.dogstats.increment(
      "proxima.api.tenantmetadata.tenant_provisioning_job.failures"
      )
    end
  end
end
