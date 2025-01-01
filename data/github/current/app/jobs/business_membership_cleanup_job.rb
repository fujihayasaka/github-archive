# typed: true
# frozen_string_literal: true

class BusinessMembershipCleanupJob < ApplicationJob
  queue_as :business_membership_cleanup

  resolve_tenant_context do |business|
    business
  end

  # Public - job to trigger cleanup for users who are no longer part of a Business
  #
  # business - Business that the users are departing
  # organization_id - if specified, will attempt to find the Organization and remove all of its
  #                   members and billing managers (overrides the user_ids parameter,
  #                   unless Organization cannot be found)
  # user_ids - list of user id's being removed from the Business (can be overridden if the
  #            organization_id parameter is specified and points to an existing Organization)
  def perform(business, organization_id: nil, user_ids: [])
    return if business.enterprise_managed_user_enabled?

    unless organization_id.nil?
      organization = Organization.find_by(id: organization_id)
      user_ids = organization.member_and_billing_manager_ids unless organization.nil?
    end

    business.remove_users_from_business(user_ids) unless user_ids.blank?
  end
end
