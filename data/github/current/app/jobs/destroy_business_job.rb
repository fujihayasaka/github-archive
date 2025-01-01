# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class DestroyBusinessJob < ApplicationJob
  queue_as :destroy_business

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  DEFAULT_JOB_TTL = T.let(4.hours, ActiveSupport::Duration)

  resolve_tenant_context do |business_id|
    Business.including_deleted.find_by(id: business_id)
  end

  sig { returns(String) }
  def self.prefix
    "destroy-business-job"
  end

  sig { params(business_id: Integer).returns(String) }
  def self.job_id(business_id)
    "#{prefix}_#{business_id}"
  end

  sig { params(business_id: Integer).returns(T.nilable(EnterpriseAccounts::JobStatus)) }
  def self.status(business_id)
    EnterpriseAccounts::JobStatus.find(job_id(business_id))
  end

  sig do
    params(
      business_id: Integer,
      actor: T.nilable(User)
    ).void
  end
  def perform(business_id, actor: nil)
    return unless business = Business.including_deleted.find_by(id: business_id)

    actor = User.ghost unless actor.present?

    status = EnterpriseAccounts::JobStatus.create(id: self.class.job_id(business_id), ttl: DEFAULT_JOB_TTL)
    status.track do
      if business.enterprise_managed?
        # Delete users associated with the EMU business
        delete_associated_emus(business, actor)

        # Return if EMU business still has associated EMU users, to avoid exposing them to the public.
        return if business.user_accounts.any?
      end

      destroy_associated_orgs(business, actor)

      # Return if business still has an associated organization, to avoid converting the org to a
      # standalone org. This is particularly important for an EMU businesses, as the orgs shouldn't be
      # exposed to the public.
      return if business.organizations.any? || business.soft_deleted_organizations.any?
      return if business.trade_compliance_delete_restriction?

      if GitHub.multi_tenant_enterprise?
        if business.feature_enabled?(:self_serve_proxima_deprovisioning)
          # call TMS deprovisioning endpoint
          # Ensure that the default timeout for the client is set to 60s
          tenant_deprovisioned = business.deprovision_tenant
          return unless tenant_deprovisioned

          success = business.delete_provisioning_request
          return unless success
        else
          # this is to prevent messy deletions
          # where we delete the EA but don't delete the associated
          # MultiTenantProvisioningRequest or deprovision the tenant
          return
        end
      end

      with_write { business.destroy! }
    end
  end

  private

  sig { params(business: Business, actor: User).void }
  def delete_associated_emus(business, actor)
    # All users associated with the EMU business
    business.user_accounts.find_each do |business_user_account|
      if user = business_user_account.user
        # Only destroy the user if valid EMU user
        next unless user.is_enterprise_managed?
        destroy_entity(user, actor)
        GitHub::CurrentTenant.set(business) if GitHub.multi_tenant_enterprise?
      end
    end
  end

  sig { params(business: Business, actor: User).void }
  def destroy_associated_orgs(business, actor)
    # Destroy all associated soft deleted orgs
    business.soft_deleted_organizations.find_each do |org|
      destroy_entity(org, actor)
      GitHub.dogstats.increment("organization", tags: ["action:destroy"])
      GitHub::CurrentTenant.set(business) if GitHub.multi_tenant_enterprise?
    end
  end

  sig { params(entity: T.any(Organization, User), actor: User).void }
  def destroy_entity(entity, actor)
    with_write do
      begin
        entity.skip_admins_presence_validation = true if entity.is_a?(Organization)
        entity.update! deleted_at: Time.now, deleted_by: actor.display_login, deleted: true
        entity.instrument :async_delete
        GlobalInstrumenter.instrument "user.destroy", {
          user: entity,
          actor: actor,
          delete_type: :OTHER,
          actor_was_staff: actor.site_admin?,
          email: entity.primary_user_email,
        }
        UserDeleteJob.perform_now(entity.id, entity.display_login)
      rescue ActiveRecord::RecordInvalid => error
        Failbot.report!(error)
      rescue ActiveRecord::RecordNotDestroyed => error
        Failbot.report!(error)
      end
    end
  end
end
