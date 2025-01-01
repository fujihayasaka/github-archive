# typed: true
# frozen_string_literal: true

class BusinessUserAccount::UpdateAttributes
  extend T::Helpers

  include GitHub::Memoizer
  include ::Licensing::BusinessUserAccount::UpdateAttributes::LicensingDependency

  MAX_ROLE_UPDATES = 1000
  SQL_BATCH_SIZE = 100

  attr_reader :business, :roles_updates_hash, :license_updates_hash, :cost_center_updates_hash, :user_account_ids

  sig { params(business: Business, user_account_ids: T.nilable(T::Array[Integer])).void }
  def initialize(business:, user_account_ids: nil)
    return unless business.include_attributes_on_user_account?

    @business = business
    @user_account_ids = user_account_ids

    @roles_updates_hash = get_roles_updates_hash
    @license_updates_hash = get_license_updates_hash
    @cost_center_updates_hash = get_cost_center_updates_hash
  end

  # Public: Performs all saves necessary for all business user accounts.
  sig { void }
  def save!
    save_roles
    save_licenses
    save_cost_centers

    nil
  end

  # Public: Saves role to business user accounts in batches.
  sig { void }
  def save_roles
    return unless roles_updates_hash

    roles_updates_hash.each do |role_value, ids|
      ids.each_slice(SQL_BATCH_SIZE) do |batch_ids|
        BusinessUserAccount.where(id: batch_ids).update_all(business_roles_bitfield: role_value)
      end
    end
    nil
  end

  # Public: Saves license to business user accounts in batches.
  # This will emit billing events for changed licenses.
  sig { void }
  def save_licenses
    return unless license_updates_hash

    license_updates_hash.each do |license_value, ids|
      ids.each_slice(SQL_BATCH_SIZE) do |batch_ids|
        BusinessUserAccount.where(id: batch_ids).update_all(ghec_license: license_value) unless batch_ids.empty?
      end
    end
    nil
  end

  # Public: Saves cost center to business user accounts in batches.
  sig { void }
  def save_cost_centers
    return unless cost_center_updates_hash

    cost_center_updates_hash.each do |cost_center, ids|
      ids.each_slice(SQL_BATCH_SIZE) do |batch_ids|
        cost_center_value = cost_center == "nil" ? nil : cost_center
        BusinessUserAccount.where(id: batch_ids).update_all(cost_center: cost_center_value)
      end
    end
    nil
  end

  # Public: Should this job be broken into batches?
  sig { returns(T::Boolean) }
  def updates_exceed_batch_size?
    # calculate_roles_bitfield_for_account is a heavy operation and scales linearly with the number of accounts,
    # so we need to process this serially in batches.
    # License and cost center updates are not as heavy, so we can process them in one go.
    accounts_with_roles_mismatches.size > MAX_ROLE_UPDATES
  end

  private

  # Private: Returns a hash of role bitfield mapped to an array of account IDs that require that role bitfield.
  # Only contains accounts that require updates.
  sig { returns(T::Hash[Integer, T::Array[Integer]]) }
  def get_roles_updates_hash
    accounts_with_roles_mismatches.take(MAX_ROLE_UPDATES).each_with_object({}) do |account, roles_updates_hash|
      role_bitfield_for_account = calculate_roles_bitfield_for_account(account)
      roles_updates_hash[role_bitfield_for_account] ||= []
      roles_updates_hash[role_bitfield_for_account] << account.id
    end
  end

  # Private: Returns a hash of cost centers mapped to an array of account IDs that require the cost center. Only
  # contains accounts that require updates.
  sig { returns(T::Hash[String, T::Array[Integer]]) }
  def get_cost_center_updates_hash
    return {} unless business.user_scoped_cost_centers? && cost_centers = business.cost_centers_with_user_id

    cost_center_updates_hash = {}
    user_ids_without_cost_center = business_user_accounts.map(&:user_id) # Start with all user IDs, and remove as we find them

    cost_centers.each do |cost_center, cost_center_user_ids|
      user_ids_without_cost_center -= cost_center_user_ids.map(&:to_i)
      accounts_needing_updates = accounts_with_mismatched_cost_center(cost_center, cost_center_user_ids)
      cost_center_updates_hash[cost_center] = accounts_needing_updates if accounts_needing_updates.any?
    end

    if user_ids_without_cost_center.any?
      # Providing nil to the cost center search, to find users that should have no cost center but have one assigned.
      accounts_needing_updates = accounts_with_mismatched_cost_center(nil, user_ids_without_cost_center)
      cost_center_updates_hash["nil"] = accounts_needing_updates if accounts_needing_updates.any?
    end

    cost_center_updates_hash
  end

  # Private: Business user accounts that have roles that do not match the business. Business is the source of truth.
  sig { returns(T::Set[BusinessUserAccount]) }
  memoize def accounts_with_roles_mismatches
    BusinessUserAccount::Roles::BUSINESS_ROLES.flat_map do |role, _|
      accounts_missing_role(role) + accounts_with_extra_role(role)
    end.uniq.to_set
  end

  # Private: Business user accounts that need a role added.
  sig { params(role: Symbol).returns(T::Array[BusinessUserAccount]) }
  def accounts_missing_role(role)
    roles_from_business(role) - roles_from_accounts(role)
  end

  # Private: Business user accounts that need a role removed.
  sig { params(role: Symbol).returns(T::Array[BusinessUserAccount]) }
  def accounts_with_extra_role(role)
    roles_from_accounts(role) - roles_from_business(role)
  end

  # Private: Calculates the role bitfield value for a given account.
  sig { params(account: BusinessUserAccount).returns(Integer) }
  def calculate_roles_bitfield_for_account(account)
    BusinessUserAccount::Roles::BUSINESS_ROLES.reduce(0) do |total, (role, value)|
      if roles_from_business(role).include?(account)
        total += value
        # For users who are unaffiliated or suspended, they can only have that single role
        return value if [:unaffiliated, :suspended].include?(role)
      end
      total
    end
  end

  # Private: Business user accounts that have cost centers that do not match the business. Input parameters are the
  # source of truth.
  sig { params(cost_center: T.nilable(String), user_ids: T::Array[Integer]).returns(T::Set[BusinessUserAccount]) }
  def accounts_with_mismatched_cost_center(cost_center, user_ids)
    user_ids.map!(&:to_i)

    if cost_center.nil?
      business_user_accounts.select { |bua| user_ids.include?(bua.user_id) && !bua.cost_center.nil? }.map(&:id).to_set
    else
      business_user_accounts.select { |bua| user_ids.include?(bua.user_id) && (bua.cost_center.nil? || bua.cost_center != cost_center) }.map(&:id).to_set
    end
  end

  sig { params(role: Symbol).returns(T::Array[BusinessUserAccount]) }
  def roles_from_business(role)
    case role
    when :server_member
      enterprise_installation_server_members
    when :server_admin
      enterprise_installation_server_admins
    when :unaffiliated
      unaffiliated_accounts
    when :member
      organization_member_buas
    when :owner
      owner_buas
    when :billing_manager
      billing_manager_buas
    when :guest_collaborator
      all_guest_collaborator_buas
    when :outside_collaborator
      outside_collaborator_buas
    when :emu_admin
      emu_admin_buas
    when :suspended
      suspended_member_buas
    else
      raise ArgumentError, "Invalid role: #{role}"
    end
  end

  # Private: Finds business user accounts that have a role saved on the business user account.
  sig { params(role: Symbol).returns(T::Array[BusinessUserAccount]) }
  def roles_from_accounts(role)
    # Memoize the BUA results to avoid long in-memory filters
    @roles_from_accounts_cache ||= {}
    return @roles_from_accounts_cache[role] if @roles_from_accounts_cache.key?(role)

    result = business_user_accounts.select { |bua| bua.business_roles.include?(role) }
    @roles_from_accounts_cache[role] = result
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def owner_buas
    owner_ids = business.owner_ids
    business_user_accounts.select { |bua| owner_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def billing_manager_buas
    billing_manager_ids = business.billing_manager_ids
    business_user_accounts.select { |bua| billing_manager_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def organization_member_buas
    organization_member_ids = business.organization_member_ids
    business_user_accounts.select { |bua| organization_member_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def suspended_member_buas
    suspended_member_ids = business.suspended_member_ids || []
    business_user_accounts.select { |bua| suspended_member_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def emu_admin_buas
    return [] unless business.enterprise_managed_user_enabled?

    emu_admin_ids = User.where(login: User.standardize_login(business.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX))
      .filter { |u| business.owner?(u) }
      .pluck(:id)
    business_user_accounts.select { |bua| emu_admin_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def all_guest_collaborator_buas
    all_guest_collaborator_ids = business.all_guest_collaborators.pluck(:id)
    business_user_accounts.select { |bua| all_guest_collaborator_ids.include?(bua.user_id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def outside_collaborator_buas
    private_outside_collaborator_ids = business.outside_collaborator_ids(
      on_repositories_with_visibility: [:private],
      include_forks: false
    )
    nonlicensed_outside_collaborator_ids = business.outside_collaborator_ids(
      on_repositories_with_visibility: [:public],
      include_forks: true
    )
    outside_collaborator_ids = (private_outside_collaborator_ids + nonlicensed_outside_collaborator_ids).uniq
    business_user_accounts.select { |bua| outside_collaborator_ids.include?(bua.user_id) }
  end

  # Private: Users that are not affiliated with the business resources.
  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def unaffiliated_accounts
    affiliated_buas = owner_buas +
      billing_manager_buas +
      organization_member_buas +
      all_guest_collaborator_buas +
      outside_collaborator_buas +
      emu_admin_buas +
      suspended_member_buas +
      enterprise_installation_server_members +
      enterprise_installation_server_admins

    affiliated_bua_ids_set = affiliated_buas.map(&:id).to_set
    business_user_accounts_set = business_user_accounts.map(&:id).to_set

    non_affiliated_bua_ids = business_user_accounts_set - affiliated_bua_ids_set
    business_user_accounts.select { |bua| non_affiliated_bua_ids.include?(bua.id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def enterprise_installation_server_members
    server_member_bua_ids = enterprise_installation_user_account_ids
      .select { |_, site_admin| !site_admin }
      .map { |id, _| id }
    business_user_accounts.select { |bua| server_member_bua_ids.include?(bua.id) }
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def enterprise_installation_server_admins
    server_admin_bua_ids = enterprise_installation_user_account_ids
      .select { |_, site_admin| site_admin }
      .map { |id, _| id }
    business_user_accounts.select { |bua| server_admin_bua_ids.include?(bua.id) }
  end

  # Private: User account IDs that are enterprise installation users.
  #
  # Returns an array of arrays, where the first element is the business user account ID and the second element
  # is a boolean indicating if the user is a site admin.
  sig { returns(T::Array[T::Array[T.any(Integer, T::Boolean)]]) }
  memoize def enterprise_installation_user_account_ids
    return [] unless business.enterprise_installations.any?

    if user_account_ids
      EnterpriseInstallationUserAccount
        .batched_scope(:business_user_account_id, values: user_account_ids)
        .pluck(:business_user_account_id, :site_admin)
    else
      BusinessUserAccount.where(business: business)
        .joins(:enterprise_installation_user_accounts)
        .pluck(
          :id,
          "enterprise_installation_user_accounts.site_admin"
        )
    end
  end

  sig { returns(T::Array[BusinessUserAccount]) }
  memoize def business_user_accounts
    ids = user_account_ids || BusinessUserAccount.where(business: business).pluck(:id)
    BusinessUserAccount.where(business: business).batched_scope(:id, values: ids).to_a
  end
end
