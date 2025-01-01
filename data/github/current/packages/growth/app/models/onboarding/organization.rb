# typed: strict
# frozen_string_literal: true

# Class that handles the logic to know if an organization is on onboarding or not.
class Onboarding::Organization
  sig { params(organization: Organization).void }
  def initialize(organization)
    @organization = organization
  end

  sig { returns(T::Boolean) }
  def enabled?
    # When organization.show_onboarding_tasks is nil, this means that the organization was created before we implemented that boolean.  If that is the case, we need to check
    # for some default conditions where we might display onboarding for the user.
    if organization.show_onboarding_tasks.nil?
      return false if GitHub.enterprise?
      return false if organization.is_enterprise_managed?
      return organization.business&.part_of_startup_program? || organization.business&.trial? || Billing::EnterpriseCloudTrial.new(organization).active?
    end

    !!organization.show_onboarding_tasks
  end

  private

  sig { returns(Organization) }
  attr_reader :organization
end
