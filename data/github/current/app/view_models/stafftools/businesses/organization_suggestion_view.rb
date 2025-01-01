# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::OrganizationSuggestionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_accessor :organization, :business

  def initialize(**args)
    super(args)
    @organization = args[:organization]
    @business = args[:business]
  end

  def org_has_business?
    organization.business.present?
  end

  def show_two_factor_confirmation_modal?
    !organization.two_factor_requirement_enabled? &&
    business.two_factor_requirement_enabled? &&

    # Org has users without 2FA enabled
    organization.affiliated_users_with_two_factor_disabled_exist?
  end
end
