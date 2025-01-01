# typed: true
# frozen_string_literal: true
#
# # This job is to be called after granting abilities for users by Business#add_users_to_organizations
class OrganizationBulkAddMembersJob < ApplicationJob
  queue_as :organization_bulk_add_members

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business|
    business
  end

  sig { params(business: Business, memberships: T::Array[[Integer, Integer]], action: Symbol, actor: User, caller_type: T.nilable(Symbol)).void }
  def perform(business:, memberships:, action:, actor:, caller_type:)
    memberships = memberships.reduce({}) do |m, r|
      m[r[0]] = (m[r[0]] || []) + [r[1]]
      m
    end
    orgs = business.organizations.where(id: memberships.values.flatten.uniq).all
    users = User.where(id: memberships.keys.uniq).all

    orgs.each do |org|
      users_added = users.filter { |user| memberships[user.id].include?(org.id) }
      with_write { org.bulk_add_organization_membership_entry(user_ids: users_added.pluck(:id), team: nil, adder: actor, caller_type: caller_type) }
      org.bulk_added_members(users: users_added, action: action, actor: actor, caller_type: caller_type)
    end

    users.each do |user|
      user.synchronize_search_index
    end
    with_write { Contribution.bulk_clear_caches_for_users(users, context: "organization_bulk_add_members_job") }

    BusinessUserAccountUpdateAttributesJob.perform_later(business, user_account_ids: business.user_accounts.where(user_id: users.pluck(:id)).pluck(:id)) unless GitHub.single_business_environment?
    business.update_license_usage
  end
end
