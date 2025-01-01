# typed: strict
# frozen_string_literal: true

# Creates BusinessUserAccounts for users with business permissions that are missing a BUA,
# and removes BusinessUserAccounts with no business permissions.
class BusinessUserAccount::SynchronizeAccounts
  extend T::Helpers

  include GitHub::Memoizer

  sig { returns Business }
  attr_reader :business

  BUA_REMOVAL_DELAY = T.let(10.minutes, ActiveSupport::Duration)
  BATCH_SIZE = T.let(100, Integer)

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  # Public: Remove BusinessUserAccounts that have no business permissions.
  sig { void }
  def remove_orphaned_accounts
    orphaned_bua_user_ids.each_slice(BATCH_SIZE) do |user_ids_batch|
      T.unsafe(business.user_accounts).remove_members(user_ids_batch)
    end
  end

  # Public: Add BusinessUserAccounts for users with business permissions that are missing a BUA.
  sig { void }
  def add_missing_accounts
    missing_user_ids.each_slice(BATCH_SIZE) do |user_ids_batch|
      ActiveRecord::Base.connected_to(role: :writing) { business.add_user_accounts(user_ids_batch) }
    end
  end

  private

  sig { returns(T::Set[Integer]) }
  def missing_user_ids
    needed_user_ids = (
      owner_ids +
      billing_manager_ids +
      organization_member_ids +
      all_guest_collaborator_ids +
      outside_collaborator_ids +
      emu_admin_ids +
      suspended_member_ids
    ).to_set
    return Set.new if needed_user_ids.empty?

    existing_user_ids = business.user_accounts.where(user_id: needed_user_ids).pluck(:user_id).to_set
    needed_user_ids - existing_user_ids
  end

  sig { returns(T::Set[Integer]) }
  def orphaned_bua_user_ids
    return Set.new unless remove_unaffiliated_users_from_business?

    business.user_accounts.exclusive_unaffiliated_role.where("created_at <= ?", BUA_REMOVAL_DELAY.ago).pluck(:user_id).to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def owner_ids
    business.owner_ids.to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def billing_manager_ids
    business.billing_manager_ids.to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def organization_member_ids
    business.organization_member_ids.to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def suspended_member_ids
    business.suspended_member_ids&.to_set || Set.new
  end

  sig { returns(T::Set[Integer]) }
  memoize def emu_admin_ids
    return Set.new unless business.enterprise_managed_user_enabled?

    User.where(login: User.standardize_login(business.shortcode, suffix: User::EnterpriseManagedDependency::ADMIN_SUFFIX))
      .filter { |u| business.owner?(u) }
      .pluck(:id).to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def all_guest_collaborator_ids
    business.all_guest_collaborators.pluck(:id).to_set
  end

  sig { returns(T::Set[Integer]) }
  memoize def outside_collaborator_ids
    private_outside_collaborator_ids = business.outside_collaborator_ids(
      on_repositories_with_visibility: [:private],
      include_forks: false
    )
    nonlicensed_outside_collaborator_ids = business.outside_collaborator_ids(
      on_repositories_with_visibility: [:public],
      include_forks: true
    )
    (private_outside_collaborator_ids + nonlicensed_outside_collaborator_ids).uniq.to_set
  end

  sig { returns(T::Boolean) }
  def remove_unaffiliated_users_from_business?
    return false if GitHub.single_business_environment? ||
      business.enterprise_managed_user_enabled? ||
      business.supports_unaffiliated_user_accounts?

    business.feature_enabled?(:bua_synchronize_removes_orphaned_accounts)
  end
end
