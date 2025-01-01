# typed: true
# frozen_string_literal: true

class DestroyBusinessJob < ApplicationJob
  extend T::Sig

  queue_as :destroy_business

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business_id|
    Business.including_deleted.find_by(id: business_id)
  end

  sig do
    params(
      business_id: Integer,
      actor: T.nilable(User)
    ).void
  end
  def perform(business_id, actor: nil)
    return unless business = Business.including_deleted.find_by(id: business_id)
    return if business.enterprise_managed? && actor.present? && !GitHub.flipper[:emu_ea_deletion].enabled?(actor)

    if business.enterprise_managed?
      # Return if EMU business has been soft deleted but still has an associated organization, to
      # avoid exposing the organization to the public.
      return if business.organizations.any?

      # Delete users associated with the EMU business
      actor = User.ghost unless actor.present?
      delete_associated_emus(business, actor)

      # Return if EMU business still has associated EMU users, to avoid exposing them to the public.
      return if business.user_accounts.any?
    end

    with_write { business.destroy! }
  end

  private

  def delete_associated_emus(business, actor)
    # All users associated with the EMU business
    business.user_accounts.find_each do |business_user_account|
      if user = business_user_account.user
        # Only destroy the user if valid EMU user
        next unless user.is_enterprise_managed?
        destroy_emu_user(user, actor)
        GitHub::CurrentTenant.set(business) if GitHub.multi_tenant_enterprise?
      end
    end
  end

  def destroy_emu_user(user, actor)
    with_write do
      begin
        user.update! deleted_at: Time.now, deleted_by: actor.display_login, deleted: true
        user.instrument :async_delete
        GlobalInstrumenter.instrument "user.destroy", {
          user: user,
          actor: actor,
          delete_type: :OTHER,
          actor_was_staff: actor.site_admin?,
          email: user.primary_user_email,
        }
        UserDeleteJob.perform_now(user.id, user.display_login)
      rescue ActiveRecord::RecordInvalid => error
        Failbot.report!(error)
      rescue ActiveRecord::RecordNotDestroyed => error
        Failbot.report!(error)
      end
    end
  end
end
