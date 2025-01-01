# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessCreatedFromOrganizationJob < ApplicationJob
  queue_as :business_created_from_organization
  retry_on_dirty_exit

  resolve_tenant_context do |business|
    business
  end

  # Public - Job that runs after a business was created from an
  # organization
  #
  # business - Business that was created
  # organization - Organization that is the first member org in the Business
  # actor - User who initiated the upgrade
  # settings_to_transfer - Array of Hash of settings that should be transferred
  #   from Organization to Business. Should look like this:
  #
  #   [
  #     {
  #       name: :first_group_of_settings,
  #       description: "First description"
  #     },
  #     {
  #       name: :second_group_of_settings
  #       description: "Second description"
  #     }
  #   ]
  def perform(business, organization, actor, settings_to_transfer = [])
    organization.suspend_billing if business.trial?

    transfer_billing_managers_from_org_to_business(business, organization, actor)
    transfer_owners_from_org_to_business_after_purchase_upgrade(business, organization, actor)
    create_business_user_accounts_for_org_members(business, organization)

    settings_to_transfer.each do |setting|
      case setting[:name]
      when :two_factor_authentication
        transfer_two_factor_authentication_from_org_to_business(business, organization, actor)
      when :ip_allow_list
        transfer_ip_allow_list_from_org_to_business(business, organization, actor)
      when :ssh_certificate_authorities
        transfer_ssh_certificate_authorities_from_org_to_business(business, organization, actor)
      when :domains
        transfer_domains_from_org_to_business(business, organization, actor)
      end
    end

    # don't send email if this job is run as part of the business creation from coupon redemption flow
    # email is sent from Business#complete_creation_from_coupon instead
    BusinessMailer.business_created_from_organization(
      business,
      organization,
      actor,
      settings_to_transfer
    ).deliver_later unless business.created_from_coupon?
  end

  private

  def transfer_billing_managers_from_org_to_business(business, organization, actor)
    organization.billing_managers.each do |manager|
      with_write do
        unless business.billing.manager?(manager) || organization.adminable_by?(manager)
          business.billing.add_manager(manager, actor: actor, send_notification: false) if business.valid_administrator_state?(manager)
        end
      end
    end
  end

  # Private - Transfer all organization admins to the newly upgraded Enterprise Account.
  #
  # Only applies to upgradees from a self-serve billing, Free/Team plan organization.
  # For all other plans and billing types, the owners are immediately transfered upon Enterprise Account creation.
  # The Free/Team plan organization purchase upgrade flow relies on waiting for successful payment before attaching
  # the organization to the new Enterprise Account. For this reason, we only do the transfer at this point.
  #
  # business - Business that was created
  # organization - Organization being upgraded
  # actor - User who initiated the upgrade
  #
  def transfer_owners_from_org_to_business_after_purchase_upgrade(business, organization, actor)
    return unless business.upgraded_from.present?
    return unless business.self_serve_payment?
    return unless business.upgraded_from_plan == "free" || business.upgraded_from_plan == "business"

    organization.admins.each do |owner|
      with_write do
        business.add_owner(owner, actor: actor, send_email_notification: false) if business.valid_administrator_state?(owner)
      end
    end
  end

  # Private: Explicitly create the BusinessUserAccount records for the org members.
  #
  # This is usually done automatically when creating a Business::OrganizationMembership,
  # however in this situation we want to ensure that BusinessUserAccounts are created for
  # org owners and billing managers who are transferred to the Business first, and then
  # BusinessUserAccounts are created for the org members.
  #
  # This avoids a possible race condition where this job and BusinessUserAccountCreateForOrganizationJob
  # run concurrently for an org to enterprise upgrade and duplicate BusinessUserAccount records
  # possibly get created.
  #
  # business - Business that was created
  # organization - Organization being upgraded
  def create_business_user_accounts_for_org_members(business, organization)
    business.add_user_accounts_for_organization_members(organization)
  end

  def transfer_two_factor_authentication_from_org_to_business(business, organization, actor)
    if organization.two_factor_requirement_enabled?
      EnforceTwoFactorRequirementOnBusinessJob.perform_later(business, actor,
        disallowed_methods: organization.insecure_two_factor_methods_disallowed? ? :insecure : [],
      )
    end
  end

  def transfer_ip_allow_list_from_org_to_business(business, organization, actor)
    return unless GitHub.ip_allowlists_available?

    with_write do
      organization.ip_allowlist_entries.update_all(owner_type: "Business", owner_id: business.id)
      business.enable_ip_allowlist(actor: actor) if organization.ip_allowlist_enabled?
      business.enable_ip_allowlist_app_access(actor: actor) if organization.ip_allowlist_app_access_enabled?
    end
  end

  def transfer_ssh_certificate_authorities_from_org_to_business(business, organization, actor)
    with_write do
      business.enable_ssh_certificate_requirement(actor) if organization.ssh_certificate_requirement_enabled?
      organization.usable_ssh_certificate_authorities.update_all(owner_type: "Business", owner_id: business.id)
    end
  end

  def transfer_domains_from_org_to_business(business, organization, actor)
    with_write do
      organization.verifiable_domains.update_all(owner_type: "Business", owner_id: business.id)
      if organization.restrict_notifications_to_verified_domains?
        business.enable_notification_restrictions(actor: actor, force: true, notify_members: false)
      end
    end
  end
end
