# typed: true
# frozen_string_literal: true

class Business::OrganizationPermission
  def initialize(business, current_user)
    @business = business
    @current_user = current_user
  end

  # Public: Can the User create a new Organization within the Business?
  #
  # Note: authorization should be performed prior to calling this method.
  #
  # check_licenses - Optional Boolean. When true, a check for sufficient
  # licenses required to create an Organization will be done. Defaults to true.
  #
  # Returns Boolean
  def can_create_organization?(check_licenses: true)
    # On GHES creating a new org does not consume licenses
    return true if GitHub.single_business_environment?

    # Disable org creation when downgraded to free
    return false if business.downgraded_to_free_plan?

    # Disable org creation when an upgrade from a free/teams-plan org
    # is in progress or payment has not yet been confirmed
    return false if business.upgrading_from_organization?

    # Disable org creation when the account is being created from a coupon
    # and the process has not yet been completed
    return false if business.being_created_from_coupon?

    # Basic plans can not create organizations
    return false if business.seats_plan_basic?

    # Metered GHEC customers pay for seats as they're consumed
    return true if business.metered_plan?

    return true unless check_licenses

    # Creating a new organization will create a new license for the current user
    # if they are not already consuming a license
    business.has_sufficient_licenses_for?(user: current_user)
  end

  private

  attr_reader :business, :current_user
end
