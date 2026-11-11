# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessMembershipCleanupJob < ApplicationJob
  queue_as :business_membership_cleanup
  retry_on_dirty_exit

  resolve_tenant_context do |business|
    business
  end

  # Public - job to trigger cleanup for users who are no longer part of a Business
  #
  # business                  - Business that the users are departing
  # organization_id           - if specified, will attempt to find the Organization and remove all of its
  #                             members and billing managers (overrides the user_ids parameter,
  #                             unless Organization cannot be found)
  # user_ids                  - list of user id's being removed from the Business (can be overridden if the
  #                             organization_id parameter is specified and points to an existing Organization)
  # remove_unaffiliated_users - if true, will remove users who are not members of any organization
  #                             in the business and don't have a Copilot license rather than converting
  #                             then to unaffiliated users (default: false)
  #
  # Returns nothing
  def perform(business, organization_id: nil, user_ids: [], remove_unaffiliated_users: false)
    return if business.enterprise_managed_user_enabled?

    unless organization_id.nil?
      organization = Organization.find_by(id: organization_id)
      user_ids = organization.member_and_billing_manager_ids unless organization.nil?
    end

    if remove_unaffiliated_users && organization_id && user_ids.present?
      copilot_user_ids = Copilot::Seat.for_assigned_user_ids_and_owner(user_ids, business).map(&:assigned_user_id)
      user_ids -= copilot_user_ids
      business.remove_members_who_are_only_members_of_these_orgs(user_ids, [organization_id])
    else
      business.cleanup_removed_users(user_ids) unless user_ids.blank?
    end
  end
end
