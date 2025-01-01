# typed: true
# frozen_string_literal: true

require "github/enterprise_accounts/kv"

module Organization::EnterpriseDependency
  extend T::Helpers
  requires_ancestor { Organization }

  COUPONS_EXCLUDED_FROM_FORCED_GHEC_UPGRADE = T.let(%w[emu-opensource opensource-foundation-ghec-100-forever opensource-ghec-actions], T::Array[String])

  # All possible settings that may be transferred from an Organization
  # to a Business during the upgrade process.
  ALL_TRANSFERABLE_SETTINGS = [
    {
      name: :two_factor_authentication,
      description: "Two-factor authentication configuration"
    },
    {
      name: :ip_allow_list,
      description: "IP allow list configuration"
    },
    {
      name: :ssh_certificate_authorities,
      description: "SSH certificate authorities configuration"
    },
    {
      name: :domains,
      description: "Verified and approved domains configuration"
    },
  ]

  # Public: Get the settings that may be transferred from an org to enterprise on upgrade.
  # Filter out any settings from ALL_TRANSFERABLE_SETTINGS that have not been set on the org.
  #
  # Returns Array of Hash.
  def transferable_settings
    return @transferable_settings if defined? @transferable_settings

    @transferable_settings = []
    transferable = Organization::EnterpriseDependency::ALL_TRANSFERABLE_SETTINGS

    if self.two_factor_requirement_enabled?
      @transferable_settings << transferable.find { |s| s[:name] == :two_factor_authentication }
    end

    if self.ip_allowlist_entries.any?
      @transferable_settings << transferable.find { |s| s[:name] == :ip_allow_list }
    end

    if self.usable_ssh_certificate_authorities.any?
      @transferable_settings << transferable.find { |s| s[:name] == :ssh_certificate_authorities }
    end

    if self.verifiable_domains.any?
      @transferable_settings << transferable.find { |s| s[:name] == :domains }
    end

    @transferable_settings
  end

  # Public: is the organization eligible for upgrading to an enterprise account?
  # An organization is eligible for upgrading to an enterprise account if:
  #   1) The organization is not in a single business environment
  #   2) The organization is not already part of an existing enterprise or soft-deleted enterprise
  #   3) The organization is on a business plus plan
  #   4) The organization has at least one owner
  #   5) The organization has not been opted out temporarily via the feature flag
  #   6) The organization is not paying for a sponsors subscription via invoice
  #   7) The organization is not in dunning if it is on card billing
  #   8) The organization has a valid Zuora subscription if it is on card billing
  #   9) The organization's trade screening record is not in either of the "hit_in_review" or "true_match" restriction states
  #
  # Returns a Boolean.
  def eligible_for_upgrade_to_enterprise?
    return false if GitHub.single_business_environment?
    return false if self.business_membership.present?
    return false unless self.business_plus?
    return false unless self.admins.any?
    return false if self.feature_enabled?(:opt_out_org_to_EA_upgrade)
    if self.billing_type == "card"
      return false if self.sponsors_invoiced?
      return false if self.dunning?
      return false if !self.plan_subscription&.has_external_subscription? && !self.has_an_active_coupon?
    end
    return false if self.trade_screening_record.hit_in_review? || self.trade_screening_record.true_match?
    true
  end

  # Public: Is the organization required to upgrade to an enterprise account?
  # Part of the upcoming forced migration of standalone GHEC organizations into enterprise accounts
  # An organization is currently exempt from the forced migration if:
  #   1) The organization is not eligible to upgrade to an enterprise account
  #   2) The organization's billing type is 'invoice'
  #   3) The organization has SAML SSO enabled
  #   4) The organization is still on the Standard terms of service
  #   5) The organization has an active coupon and is part of one of the excluded coupon programs
  #   6) The organization has an incomplete pending plan change
  #
  # Returns a Boolean
  def required_to_upgrade_to_enterprise?
    return false unless self.eligible_for_upgrade_to_enterprise?
    return false if self.billing_type == "invoice"
    return false if self.saml_sso_enabled?
    return false unless self.terms_of_service.corporate?
    return false if self.has_an_active_coupon? && COUPONS_EXCLUDED_FROM_FORCED_GHEC_UPGRADE.include?(coupon.code)
    return false if self.incomplete_pending_plan_changes.present?
    true
  end

  # Public: Upgrades the organization to an enterprise account.
  # Creates a new business and adds the upgrading organization.
  # Existing configuration settings and billing are transferred over.
  # Instruments success or failure of the upgrade.
  #
  # Returns the Business::Creator object.
  def perform_direct_upgrade_to_enterprise(params, actor)
    business_params = params.require(:business).permit(
      :name,
      :slug,
      :shortcode
    )

    business_creator = Business::Creator.new(
      business_params: business_params.merge(
        can_self_serve: true,
        owners: self.admins,
        billing_email: self.billing_email,
        seats: self.seats,
        customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
          billing_type: self.billing_type,
          billing_end_date: self.billed_on.present? ? T.must(self.billed_on) - 1.day : nil
        )),
      organization: self,
      actor: actor,
      settings_to_transfer: selected_settings(params),
    )

    organization_previous_customer_id = self.customer&.id

    if self.has_an_active_coupon?
      organization_coupon_code = self.coupon.code
    end

    if self.has_unlimited_seat_coupon?
      business_creator.business.seats = self.filled_seats
    end

    if business_creator.valid?
      business = business_creator.business
      business.organization_direct_upgraded!
      business_creator.save!
      business.set_org_upgrade_onboarding_notice(initiating_owner: actor, organization: self)
      SponsorsBusinessOrgOnboardingJob.perform_later(organization: T.unsafe(self), actor: actor)
      instrument_upgrade_to_enterprise_account(
        business,
        actor,
        coupon_transfer_attempted: organization_coupon_code.present?,
        coupon_transfer_succeeded: business.reload.has_an_active_coupon?,
        coupon_code: organization_coupon_code,
        previous_customer_id: organization_previous_customer_id,
      )
      business.enable_automatic_self_serve_payment(actor, update_zuora_account: false) if should_enable_auto_pay_after_upgrade?
    else
      instrument_upgrade_to_enterprise_failure(
        actor,
        has_active_coupon: organization_coupon_code.present?,
        coupon_code: organization_coupon_code,
        error_message: business_creator.error_message,
        slug: business_creator.business.slug
      )
    end

    business_creator
  end

  # Public: is the organization eligible to upgrade their org into a self-serve enterprise account?
  # An organization is eligible for a purchase upgrade into an enterprise account if:
  #   1) The organization is not in a single business environment
  #   2) The organization is not already part of an existing enterprise or soft-deleted enterprise
  #   3) The organization is on a free or team plan
  #   4) The organization is on card billing type
  #   5) The organization has at least one owner
  #   6) The organization is not currently in progress of being upgraded
  #
  # Returns a Boolean.
  def eligible_for_purchase_upgrade_to_enterprise?(actor: nil, skip_in_progress_check: false)
    return false if GitHub.single_business_environment?
    return false if self.business_membership.present?
    return false if self.business_plus?
    return false if self.invoiced?
    return false unless self.admins.any?
    return false if !skip_in_progress_check && self.upgrade_to_enterprise_in_progress?
    true
  end

  # Public: is the organization eligible to be selected into an enterprise account trial?
  # An organization is eligible for inclusion in an enterprise account trial if:
  #   1) The organization is not in a single business environment
  #   2) The organization is not already part of an existing enterprise or soft-deleted enterprise
  #   3) The organization is on a free or team plan
  #   4) The organization is on card billing type
  #   5) The business has enough licenses available to include the organization
  #   6) The organization does not have any marketplace subscription items
  #   7) The organization is not currently in the process of being upgraded to an EA
  #
  # Returns a Boolean.
  def selectable_for_enterprise_trial?(business)
    return false if GitHub.single_business_environment?
    return false if self.business_membership.present?
    return false if self.business_plus?
    return false if self.invoiced?
    return false unless business.has_sufficient_licenses_for_organization?(self)
    return false if self.active_marketplace_listing_subscription_items.any?
    return false if self.upgrade_to_enterprise_in_progress?
    true
  end

  def selectable_for_business_created_from_coupon?(user)
    return false unless user.feature_enabled?(:new_ea_creation_from_coupon)
    return false if GitHub.single_business_environment?
    return false if self.business_membership.present?
    return false if self.business_plus?
    return false if self.upgrade_to_enterprise_in_progress?
    return false if self.invoiced?
    return false if self.dunning?
    true
  end

  # Public: Is the organization currently in progress of being upgraded into a self-serve
  # enterprise account?
  #
  # Returns a Boolean
  def upgrade_to_enterprise_in_progress?
    upgrade_to_enterprise_in_progress_value.present?
  end

  # Public: The business that the organization is currently in progress of being upgraded
  # into.
  #
  # Returns a Business
  def upgrade_to_enterprise_in_progress
    id = upgrade_to_enterprise_in_progress_value
    return nil unless id.present?
    Business.find(id.to_i)
  end

  # Public: Marks the organization as in progress of being upgraded into a self-serve
  # enterprise account
  def upgrade_to_enterprise_in_progress!(business)
    EnterpriseAccounts::KV.store.set(upgrade_to_enterprise_in_progress_key, business.id.to_s, expires: 5.days.from_now)
  end

  # Public: Unmarks the organization as in progress of being upgraded into a self-serve
  # enterprise account
  def clear_upgrade_to_enterprise_in_progress!
    EnterpriseAccounts::KV.store.del(upgrade_to_enterprise_in_progress_key)
  end

  # Internal: Return all user ids of organization members that are not also
  # members of the organization's business for other reasons, including
  # membership in another business organization, or direct membership to the business
  # as an admin or billing manager
  #
  # Returns a list of user ids that only exist in this business org
  def unique_business_member_ids
    return [] if GitHub.single_business_environment? || business.nil?

    business = T.must(self.business)
    outside_business_orgs = (business.organizations - [self])
    outside_business_member_ids = outside_business_orgs.each_with_object(Set.new) do |organization, ids|
      ids.merge(Organization::LicenseAttributer.new(organization).user_ids)
    end

    outside_business_member_ids.
      merge(business.owners.pluck(:id)).
      merge(business.billing_manager_ids)

    (Organization::LicenseAttributer.new(self).user_ids - outside_business_member_ids).to_a
  end

  # Public: Returns enterprise owners for an enterprise-owned organization.
  #
  # query - optional - String to filter returned users based on their login.
  # order_by - optional - Hash representing values to order by field and direction:
  # order_by_field     - String specifying the sort field. Supported: "LOGIN"
  # order_by_direction - String specifying the sort direction. Supported: "ASC", "DESC". Default: "ASC"
  #
  # Returns an ActiveRecord::Relation for the organization's enterprise owners.
  def async_enterprise_owners(query: nil, order_by: nil)
    return Promise.resolve([]) unless self.business

    Promise.resolve(
      T.must(self.business).admins(
        query: query,
        role: :owner,
        order_by_field: order_by&.dig(:field),
        order_by_direction: order_by&.dig(:direction))
      .includes(:profile)
    )
  end

  # Public: Returns enterprise owners who are neither a member nor an owner of the enterprise-owned organization.
  #
  # query - optional - String to filter returned users based on their login.
  # order_by - optional - Hash representing values to order by field and direction:
  # order_by_field     - String specifying the sort field. Supported: "LOGIN"
  # order_by_direction - String specifying the sort direction. Supported: "ASC", "DESC". Default: "ASC"
  #
  # Returns an ActiveRecord::Relation for the organization's enterprise owners who are unaffiliated with the organization.
  def async_unaffiliated_enterprise_owners(query: nil, order_by: nil)
    return Promise.resolve([]) unless self.business

    business = T.must(self.business)
    business_owner_ids = business.admins(role: :owner).pluck(:id)
    org_member_ids = self.members.pluck(:id)

    Promise.resolve(
      business.admins(
        query: query&.gsub("role:unaffiliated", ""),
        role: :owner,
        order_by_field: order_by&.dig(:field),
        order_by_direction: order_by&.dig(:direction))
      .includes(:profile)
      .where(id: business_owner_ids - org_member_ids)
    )
  end

  # Public: Returns enterprise owners who are owners or members of the enterprise-owned organization.
  #
  # people_query - optional - Organization::People::Query object filter returned users based on:
  #                           query, organization, current user, and role.
  # order_by - optional - Hash representing values to order by field and direction:
  # order_by_field     - String specifying the sort field. Supported: "LOGIN"
  # order_by_direction - String specifying the sort direction. Supported: "ASC", "DESC". Default: "ASC"
  #
  # Returns an ActiveRecord::Relation for the organization's enterprise owners.
  def async_affiliated_enterprise_owners(people_query: nil, order_by: nil)
    return [] unless self.business

    owners = T.must(self.business).admins(
      role: :owner,
      order_by_field: order_by&.dig(:field),
      order_by_direction: order_by&.dig(:direction))
    .includes(:profile)

    Promise.resolve(Organization::People::Search.new(query: people_query, users: owners).call)
  end

  # Public: Returns whether the organization is owned by a business which is on a metered plan.
  #
  # Returns a Boolean.
  def owned_by_metered_plan_business?
    return false unless self.business.present?
    T.must(self.business).metered_plan?
  end

  # Public: Returns whether the organization is owned by a business which is on a metered plan, and
  # the business is on trial.
  #
  # Returns a Boolean.
  def owned_by_metered_plan_trial_business?
    return false unless owned_by_metered_plan_business?
    T.must(self.business).trial?
  end

  private

  def should_enable_auto_pay_after_upgrade?
    return false unless business = self.business
    return false if business.invoiced?
    return false if business.customer&.auto_pay_reasons&.any?
    true
  end

  def instrument_upgrade_to_enterprise_account(business, actor, coupon_transfer_attempted: false, coupon_transfer_succeeded: false, coupon_code: nil, previous_customer_id: nil)
    GlobalInstrumenter.instrument("enterprise_account.organization_upgrade", {
      organization_id: self.id,
      enterprise_id: business.id,
      actor_id: actor.id,
      organization_previous_plan: business.upgraded_from_plan,
      organization_previous_customer_id: previous_customer_id,
      billing_type: business.billing_type,
      status: :DIRECT_UPGRADED,
      coupon_transfer_attempted: coupon_transfer_attempted,
      coupon_transfer_succeeded: coupon_transfer_succeeded,
      coupon_code: coupon_code,
    })

    GitHub.instrument("business.upgrade_from_organization", org: self)
  end

  def instrument_upgrade_to_enterprise_failure(actor, has_active_coupon: false, coupon_code: nil, error_message: nil, slug: nil)
    GlobalInstrumenter.instrument("enterprise_account.organization_upgrade_failure", {
      organization_id: self.id,
      actor_id: actor.id,
      organization_plan: self.plan.name,
      billing_type: self.billing_type,
      has_active_coupon: has_active_coupon,
      coupon_code: coupon_code,
      error_message: error_message,
      slug: slug
    })
  end

  def selected_settings(params)
    self.transferable_settings.select do |setting|
      params["transfer_#{setting[:name]}"] == "1"
    end
  end

  def upgrade_to_enterprise_in_progress_key
    "org-enterprise-upgrade-in-progress.#{id}"
  end

  def upgrade_to_enterprise_in_progress_value
    EnterpriseAccounts::KV.store.get(upgrade_to_enterprise_in_progress_key).value { nil }
  end
end
