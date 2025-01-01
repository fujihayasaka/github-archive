# typed: true
# frozen_string_literal: true

module User::BusinessDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include Business::TenantContext

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
    before_destroy :verify_no_owned_businesses
  end

  # An Organization has_one :business, but a vanilla User never has a business.
  def business
    nil
  end

  def async_business
    Promise.resolve(nil)
  end

  sig { override.returns(T.nilable(Business)) }
  def resolve_tenant
    FeatureFlag.vexi.enabled?(:memex_resolve_tenant, default: false) ? enterprise_managed_business : nil
  end

  # Verify that the user doesn't own any businesses before it is deleted.
  #
  # Returns a Boolean
  def verify_no_owned_businesses
    return true if GitHub.enterprise? || enterprise_managed_business.present?
    owned_businesses = businesses(membership_type: :admin)
    if owned_businesses.any?
      errors.add(:enterprises, "You must remove yourself as an owner of all enterprises")

      throw :abort
    else
      true
    end
  end

  # Returns true if this account is part of a business
  # which is managed by sales rather than being self-serve
  # Always false for individual users,
  # only true when an organization is a member of a business
  # and that business has can_self_serve disabled.
  #
  # Returns a Boolean.
  def in_a_sales_managed_business?
    business && !business.can_self_serve?
  end

  # Public: The IDs of businesses of which this user is a member.
  #
  # A "member" is defined as either:
  # - An admin of a business
  # - A billing manager of a business
  # - A member of an org that is owned by a business
  #
  # membership_type - A Symbol representing user membership type. Businesses
  #   matching the user membership type will be returned. Must be one of one of the following:
  #
  #   - :all - Returns all businesses in which the user is a member.
  #   - :admin - Returns all businesses in which the user is an admin.
  #   - :billing_manager - Returns all businesses in which the user is a billing manager.
  #   - :org_membership - Returns all businesses in which the user is a member of an org
  #   - :support_entitled - Returns all businesses in which the user is a member and is support entitled
  #     that is owned by the business.
  #
  #   Defaults to :all.
  # A user holds a GHEC license if he is member of 1 or more organizations in the business
  # - valid_license: true returns membership information for users holding an active license
  # - valid_license: false returns membership information for ALL enterprise users irrespective of their license status.
  # - include_unaffiliated: true includes businesses that the user is an unaffiliated member in
  #
  # Returns a Promise
  def async_business_ids(membership_type: :all, valid_license: false, include_unaffiliated: false)
    return Promise.resolve([]) if EnterpriseAttestation.contractor?(id)
    return Promise.resolve([]) if self.guest_collaborator?
    case membership_type
    when :all
      Promise.resolve(
        business_admin_ability_ids |
        # billing managers that use a license will be picked up by membership_via_org_ids below
        (valid_license ? [] : business_billing_management_ability_ids) |
        membership_via_org_ids |
        businesses_through_business_user_accounts(valid_license: valid_license) |
        (include_unaffiliated ? business_unaffiliated_member_ids : [])
      )
    when :admin
      Promise.resolve(business_admin_ability_ids)
    when :billing_manager
      Promise.resolve(business_billing_management_ability_ids)
    when :org_membership
      Promise.resolve(membership_via_org_ids)
    when :support_entitled
      Promise.resolve(business_support_entitled_ids)
    when :unaffiliated
      Promise.resolve(business_unaffiliated_member_ids)
    else
      raise ArgumentError, "membership_type must be one of :all, :admin, :billing_manager, :org_membership, :unaffiliated"
    end
  end

  # Public: The business IDs in which this user is a member.
  #
  # Synchronous version of async_business_ids
  #
  # Returns an array of IDs
  def business_ids(membership_type: :all, valid_license: false, include_unaffiliated: false)
    async_business_ids(membership_type: membership_type, valid_license: valid_license, include_unaffiliated: include_unaffiliated).sync
  end

  def async_businesses(membership_type: :all, valid_license: false, include_unaffiliated: false)
    async_business_ids(membership_type: membership_type, valid_license: valid_license, include_unaffiliated: include_unaffiliated).then do |ids|
      Business.where(id: ids.compact.uniq)
    end
  end

  # The businesses in which the user is a member.
  #
  # Returns an ActiveRecord relation
  def businesses(membership_type: :all, valid_license: false, include_unaffiliated: false)
    ids = business_ids(membership_type: membership_type, valid_license: valid_license, include_unaffiliated: include_unaffiliated)
    Business.where(id: ids.compact.uniq)
  end

  def is_business_member?(business_id, valid_license: false)
    business_ids(valid_license: valid_license).any?(business_id)
  end

  # A version of is_business_member? that checks if the user is a business member.
  # Short circuits rather than colllecting all related IDs and checking if the business_id is in the list.
  # Uses the async_business_ids defaults
  # And the only other difference is that we use unscoped org ids for the membership_via_org_ids check
  def cap_enforcement_is_business_member?(business_id)
    return false if EnterpriseAttestation.contractor?(id)
    return false if self.guest_collaborator?
    return true if has_business_admin_ability_id?(business_id)
    return true if has_business_billing_management_ability_id?(business_id)
    return true if membership_via_org_ids(scoped_organization_ids: false).any?(business_id)
    return true if businesses_through_business_user_accounts(valid_license: false).any?(business_id)
    false
  end

  # Public: obtain the internal repositories to which the user has access via business membership.
  # It does not take into consideration explicit access (direct/indirect) to the repo.
  #
  # Returns an ActiveRecord::Relation of Repositories
  def internal_repositories
    return guest_collaborator_internal_repositories if self.guest_collaborator?

    ids = business_ids(valid_license: true)
    return Repository.none if ids.empty?

    Repository.joins(:internal_repository).where("internal_repositories.business_id IN (?)", ids)
  end

  def internal_repo_ids
    return guest_collaborator_internal_repositories.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ repositories.id")) if self.guest_collaborator?

    ids = business_ids(valid_license: true)
    return Repository.none if ids.empty?

    Repositories.domain.internal_repo_ids_by_business_ids(business_ids: ids, active_only: false)
  end
  alias_method :internal_repository_ids, :internal_repo_ids


  def orgs_via_business_membership
    if GitHub.single_business_environment?
      Organization.all
    else
      Organization.where(id: org_ids_via_business_membership)
    end
  end

  # All organizations from all the businesses that the user belongs to.
  def org_ids_via_business_membership
    return @org_ids_via_biz_membership if defined?(@org_ids_via_biz_membership)
    @org_ids_via_biz_membership = if GitHub.single_business_environment?
      Organization.all.pluck(:id)
    else
      Business::OrganizationMembership.where(business_id: business_ids).pluck(:organization_id)
    end
  end

  # All organizations the user belongs to directly or has indirect access via business membership or outside collaborator status.
  # Useful for when trying to identify all possible orgs which should undergo a conditional access policy
  def direct_and_indirect_orgs
    if GitHub.single_business_environment?
      @direct_and_indirect_orgs ||= Organization.all
    else
      @direct_and_indirect_orgs ||= Organization.where(id: direct_and_indirect_org_ids)
    end
  end

  def direct_and_indirect_org_ids
    if GitHub.single_business_environment?
      @direct_and_indirect_org_ids ||= Organization.all.pluck(:id)
    elsif self.feature_flag_enabled?(:cap_filter_consider_outside_collabs, default: false)
      @direct_and_indirect_org_ids ||= (authorizable_organization_ids + org_ids_via_business_membership).uniq
    else
      @direct_and_indirect_org_ids ||= (organization_ids + org_ids_via_business_membership).uniq
    end
  end

  private

  def guest_collaborator_internal_repositories
    # Guest collaborators should not see internal repositories they don't have explicit access to in organizations that have a base permission of :none ('No permission'). This query returns internal repositories for a guest collaborator when:
    # 1. They belong to the organization
    # 2. The organization has a base permission of 'read' or greater
    base_perm = :read
    guest_collaborator_organization_ids = filter_guest_collaborator_organization_ids(organization_ids: organization_ids, role: base_perm)

    Repository.joins(:internal_repository).where("internal_repositories.business_id IN (?) AND repositories.organization_id IN (?)", membership_via_org_ids, guest_collaborator_organization_ids)
  end

  # This method filters an array of organization ids based on their default repository permissions.
  # This method is specifically used for guest collaborators.
  sig { params(organization_ids: T::Array[Integer], role: Symbol).returns(T::Array[Integer]) }
  def filter_guest_collaborator_organization_ids(organization_ids:, role:)
    organizations = Organization.where(id: organization_ids).to_a
    organizations.select! { |org| org.default_repository_permission == role || role_greater_than_default?(role, org.default_repository_permission) }
    organizations.filter_map(&:id)
  end

  # If the org's default repository permission is greater or equal to the passed in role, return true
  sig { params(role: Symbol, default_role: Symbol).returns(T::Boolean) }
  def role_greater_than_default?(role, default_role)
    role_action = Ability::actions[role]
    default_role_action = Ability::actions[default_role]

    return false if role_action.nil? || default_role_action.nil?

    default_role_action >= role_action
  end

  # IDs of businesses where the user has a direct admin ability on a business.
  def business_admin_ability_ids
    return [] if new_record?
    return [] if ability_delegate.nil?
    return @business_admin_ability_ids if defined?(@business_admin_ability_ids)
    @business_admin_ability_ids = Ability.where(
        subject_type: "Business",
        actor_id: self,
        actor_type: self.ability_type,
        priority: Ability.priorities[:direct],
        action: Ability.actions[:admin],
    ).pluck(:subject_id)
  end

  # True if the user has a direct admin ability on the provided business.
  def has_business_admin_ability_id?(business_id)
    return false if new_record?
    return false if ability_delegate.nil?
    return @has_business_admin_ability_id if defined?(@has_business_admin_ability_id)
    @has_business_admin_ability_id = Ability.where(
        subject_type: "Business",
        actor_id: self,
        actor_type: self.ability_type,
        priority: Ability.priorities[:direct],
        action: Ability.actions[:admin],
        subject_id: business_id,
    ).any?
  end

  # IDs of businesses where the user has an ability on the business billing management.
  def business_billing_management_ability_ids
    return [] if new_record?
    return [] if ability_delegate.nil?
    return @business_billing_management_ability_ids if defined?(@business_billing_management_ability_ids)
    @business_billing_management_ability_ids = Ability.where(
        subject_type: "Business::BillingManagement",
        actor_id: self,
        actor_type: self.ability_type,
        priority: Ability.priorities[:direct],
    ).pluck(:subject_id)
  end

  # True if the user has a direct admin ability on the provided business billing management.
  def has_business_billing_management_ability_id?(business_id)
    return false if new_record?
    return false if ability_delegate.nil?
    return @has_business_billing_management_ability_id if defined?(@has_business_billing_management_ability_id)
    @has_business_billing_management_ability_id = Ability.where(
        subject_type: "Business::BillingManagement",
        actor_id: self,
        actor_type: self.ability_type,
        priority: Ability.priorities[:direct],
        subject_id: business_id,
    ).any?
  end

  # IDs of businesses where the user has a SupportEntitlee ability and is a member
  def business_support_entitled_ids
    return [] if new_record?
    return [] if ability_delegate.nil?
    return @business_support_entitled_ids if defined?(@business_support_entitled_ids)
    support_entitlee = Business::SupportEntitlee.new(self)
    @business_support_entitled_ids = support_entitlee.abilities.pluck(:subject_id) & membership_via_org_ids
  end

  # IDs of businesses that include an org in which the user is a member.
  # scoped_organization_ids - if true, the organization IDs provided to the organization membership lookup are scoped (if applicable)
  def membership_via_org_ids(scoped_organization_ids: true)
    if scoped_organization_ids
      return @membership_via_org_ids if defined?(@membership_via_org_ids)
      @membership_via_org_ids = ::Business::OrganizationMembership.where(organization_id: organization_ids).distinct.pluck(:business_id)
    else
      return @membership_via_org_ids_unscoped if defined?(@membership_via_org_ids_unscoped)
      @membership_via_org_ids_unscoped = ::Business::OrganizationMembership.where(organization_id: organization_filter.unscoped_ids).distinct.pluck(:business_id)
    end
  end

  # If the query is for only licensed emus, don't return anything here since membership_via_org_ids will account for valid licensed emus (typically used in access control for an emu in a business)
  # Else return business that the user is a member of (typically used in views/user's business associations)
  def businesses_through_business_user_accounts(valid_license: false)
    return [] if !is_enterprise_managed?
    # https://github.com/github/gitcoin/issues/9043
    # Old behavior: EMU user in a business with VSS licenses and no org membership can see internal repos
    # New behavior: EMU user in a business with VSS licenses and no org membership cannot see internal repos
    # `emu_vss_business` - when this flag is disabled, customers will experience the new behavior.
    #                    - this ensures any new EMU signing up with VSS will get the new behavior automatically.
    #                    - when this flag is enabled, customers will experience the old behavior.
    # Once this is fully rolled out, the code will simply be:
    # return [] if valid_license
    if valid_license && FeatureFlag.vexi.enabled?(:emu_vss_business, enterprise_managed_business, default: false)
      GitHub.dogstats.increment("internal_repo_visibility_fix.enabled", tags: ["enterprise:#{enterprise_managed_business.slug}", "user:#{login}"])
    elsif valid_license
      return []
    end
    business_user_accounts.pluck(:business_id)
  end

  # IDs of businesses that support unaffiliated accounts and the user is an unaffiliated member.
  # Since for unaffiliated EMUs the users are already returned this query can be skipped.
  def business_unaffiliated_member_ids
    return [] if is_enterprise_managed?
    return @business_unaffiliated_member_ids if defined?(@business_unaffiliated_member_ids)
    ids = business_user_accounts.exclusive_unaffiliated_role.pluck(:business_id)
    @business_unaffiliated_member_ids = Business.where(id: ids).select { |b| b.supports_unaffiliated_user_accounts? }.pluck(:id)
  end
end
