# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SoftDeleteBusinessJob < ApplicationJob
  queue_as :soft_delete_business

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  class SoftDeleteBusinessSubscriptionCancellationError < StandardError; end

  attr_reader :business
  BATCH_SIZE = 100

  resolve_tenant_context do |business_id|
    Business.including_deleted.find_by(id: business_id)
  end

  # Perform required background tasks when a Business is soft-deleted.
  sig do
    params(
      business_id: Integer,
      self_serve: T::Boolean,
      actor: T.nilable(User)
    ).void
  end
  def perform(business_id, self_serve: false, actor: nil)
    return unless @business = Business.deleted.find_by(id: business_id)

    destroy_enterprise_installations
    soft_delete_all_organizations(actor, self_serve)

    close_zuora_subscription(self_serve)
    with_write { business.cancel_subscription_items!(force: true) }

    if business.enterprise_managed?
      sign_out_all_users(:emu_session_revoked)

      if business.external_provider.present? && business.external_provider.external_identity_sessions.any?
        destroy_external_provider_sessions
      end
    end
  end

  private

  def destroy_enterprise_installations
    # EnterpriseInstallations get destroyed so that the customer is not left with
    # GHES installations connected to a soft-deleted Business which they have
    # no way of disconnecting.
    EnterpriseInstallation.throttle_writes_with_retry do
      business.enterprise_installations.destroy_all
    end
  end

  def close_zuora_subscription(self_serve)
    if business.plan_subscription
      CloseOutZuoraSubscriptionJob.perform_later \
        zuora_subscription_number: business.plan_subscription.zuora_subscription_number,
        plan_subscription: business.plan_subscription,
        collect_payment: self_serve
    end
  end

  def destroy_external_provider_sessions
    ExternalIdentitySession.by_sso_provider(business.external_provider).active.in_batches(of: BATCH_SIZE) do |batch|
      ExternalIdentitySession.throttle_writes_with_retry do
        batch.delete_all
      end
    end
  end

  def sign_out_all_users(reason)
    UserSession.where(user_id: user_ids, revoked_at: nil).in_batches(of: BATCH_SIZE) do |batch|
      UserSession.throttle_writes_with_retry do
        batch.update_all(revoked_at: Time.now, revoked_reason: reason.to_s)
      end
    end
  end

  def soft_delete_all_organizations(actor, self_serve)
    business.organizations.active.in_batches(of: BATCH_SIZE) do |batch|
      Organization.throttle_writes_with_retry do
        batch.each do |org|
          org.skip_admins_presence_validation = true
          org.soft_delete!(actor, site_admin_deletion: !self_serve, remove_from_business: false)
        end
      end
    end
  end

  def user_ids
    business.user_accounts.pluck(:user_id).compact
  end
end
