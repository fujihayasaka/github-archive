# typed: true
# frozen_string_literal: true

class Business::OrganizationMembership < ApplicationRecord::Domain::Users
  include ActionView::Helpers::TextHelper

  self.table_name = "business_organization_memberships"

  # Public: Used to hold the User deleting this record for #update_plan_subscription_customer.
  attr_accessor :actor

  # Public: Used to hold a Boolean to determine if an organization is being added to a business
  # through an organization to enterprise upgrade.
  attr_accessor :organization_upgrade

  belongs_to :business
  belongs_to :organization

  validates :business, presence: true
  validates :organization_id, uniqueness: { message: "is already associated with an enterprise account" }
  validate  :ensure_business_has_enough_seats, on: :create

  after_create_commit :instrument_create
  after_destroy_commit :instrument_destroy

  after_create_commit :migrate_organization_to_business_billing, if: -> { GitHub.billing_enabled? }
  after_create_commit :create_business_user_accounts_for_org_members, unless: -> { GitHub.single_business_environment? }

  after_commit :sync_default_repository_permission
  after_commit :update_business_license_usage

  before_destroy :sync_business_policies
  before_destroy :update_organization_notification_delivery_restrictions
  after_destroy_commit :business_members_cleanup, unless: -> { T.bind(self, Business::OrganizationMembership); GitHub.single_business_environment? || business&.enterprise_managed_user_enabled? }
  after_destroy_commit :update_plan_subscription_customer, if: -> { GitHub.billing_enabled? }

  around_save :sync_two_factor_requirement,
              if: -> { T.bind(self, Business::OrganizationMembership); organization_id_changed? || business_id_changed? }

  after_commit :update_private_search_on_orgs, on: [:create, :destroy]

  # Public: In case the github-enterprise org is added to the single global business,
  # this will exclude it.
  scope :excluding_github_enterprise_org, -> do
    joins(:organization).merge(Organization.excluding_github_enterprise_org)
  end

  private

  def instrument_create
    T.must(business).instrument(
      :add_organization,
      org: organization,
      organization_upgrade: organization_upgrade
    )
  end

  def instrument_destroy
    T.must(business).instrument :remove_organization, org: organization
  end

  def update_private_search_on_orgs
    UpdatePrivateSearchOnEnterpriseOrgsJob.perform_later(
      T.must(self.business).id,
      { entry_point: :business_organization_membership_update_private_search_on_orgs }
    )
  end

  def ensure_business_has_enough_seats
    return if business.nil? || organization.nil?

    # Creating a Business::OrganizationMembership does not create any new
    # users, so this validation should never cause the creation to fail on
    # GitHub Enterprise where the business (instance) never needs enough seats
    # to add orgs to the global business.
    return if GitHub.single_business_environment?

    # Businesses on a metered plan do not require seats to be purchased ahead of time.
    business = T.must(self.business)
    organization = T.must(self.organization)
    return if business.metered_plan?

    unless business.has_sufficient_licenses_for_organization?(organization)
      seats_consumed_by_organization = business.additional_licenses_consumed_by_organization(organization)
      extra_seats_required = business.additional_licenses_required_for_organization(organization)
      errors.add(:base, "Insufficient seats to add this organization (#{pluralize(seats_consumed_by_organization, "seat")} required to add #{organization.login}, #{extra_seats_required} more must be purchased for the enterprise account)")
    end
  end

  def migrate_organization_to_business_billing
    BusinessOrganizationBillingJob.perform_later(T.must(business), T.must(organization))
  end

  def create_business_user_accounts_for_org_members
    # If organization_upgrade has been manually set to true, skip creating
    # BusinessUserAccount records at this point, which will instead be
    # created by BusinessCreatedFromOrganizationJob after org owners and
    # billing managers have been transferred.
    return if organization_upgrade

    T.must(business).add_user_accounts_for_organization_members(organization)
  end

  def update_plan_subscription_customer
    Billing::DetachOrganizationFromBusinessCustomerJob.perform_later(business, organization,
      actor: actor)
  end

  # Internal: Enqueues a job to do cleanup for users who are no longer part of the business
  #   - delete BusinessUserAccount's
  #   - unlink SAML ExternalIdentity's (SCIM-provisioned identities are preserved)
  #   - run the RemoveBizUserForksJob job to clean up forks
  #
  # Returns nothing
  def business_members_cleanup
    return if business.nil? || organization.nil?
    BusinessMembershipCleanupJob.perform_later(
      T.must(business),
      organization_id: T.must(organization).id,
    )
  end

  # Internal: Sync any default repository permission changes if the business
  # membership changes
  def sync_default_repository_permission
    organization&.sync_default_repository_permission(actor: organization)
  end

  def update_business_license_usage
    business&.update_license_usage
  end

  def sync_two_factor_requirement
    organization_2fa_required = organization&.two_factor_requirement_enabled?

    yield

    # if an Organization is added to a Business that requires 2fa, enforce 2fa on the organization
    if business&.two_factor_requirement_enabled? && business&.two_factor_required_policy? &&
      (organization_2fa_required == false)
      EnforceTwoFactorRequirementOnOrganizationJob.perform_later(organization, organization)
    end
  end

  def sync_business_policies
    return if business.nil? || self.organization.nil? || business&.trial? || business&.trial_expired?
    except = [
      Configurable::IpAllowlistEnabled::KEY,
      Configurable::IpAllowlistAppAccessEnabled::KEY,
      Configurable::MembersCanInviteOutsideCollaborators::KEY,
    ]

    organization = T.must(self.organization)
    policies = T.must(business).configuration_entries.where(final: true).where.not(name: except)
    policies.each do |configuration_entry|
      organization.config.set(configuration_entry.name, configuration_entry.value, organization)
    end
  end

  def update_organization_notification_delivery_restrictions
    return if self.organization.nil?
    organization = T.must(self.organization)
    if organization.restrict_notifications_to_verified_domains? &&
      !organization.restrict_notifications_to_verified_domains_policy? &&
      organization.verifiable_domains.verified_or_approved.empty?
      organization.disable_notification_restrictions(actor: organization)
    end
  end
end
