# typed: strict
# frozen_string_literal: true

class DestroyBusinessJob < ApplicationJob
  queue_as :destroy_business

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business_id|
    Business.including_deleted.find_by(id: business_id)
  end

  sig { params(business_id: Integer).returns(String) }
  def self.job_id(business_id)
    "destroy-business-job_#{business_id}"
  end

  sig { params(business_id: Integer).returns(T.nilable(JobStatus)) }
  def self.status(business_id)
    JobStatus.find(job_id(business_id))
  end

  sig do
    params(
      business_id: Integer,
      actor: T.nilable(User)
    ).void
  end
  def perform(business_id, actor: nil)
    return unless business = Business.including_deleted.find_by(id: business_id)
    return if business.enterprise_managed? && actor.present? && !actor.feature_enabled?(:emu_ea_deletion)

    actor = User.ghost unless actor.present?

    status = JobStatus.create(id: self.class.job_id(business_id), ttl: 4.hours)
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
