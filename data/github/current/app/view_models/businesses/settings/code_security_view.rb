# typed: true
# frozen_string_literal: true

class Businesses::Settings::CodeSecurityView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :params

  PAGE_SIZE = 50

  def initialize(**args)
    super(args)
    @business = args[:business]
    @page = args[:page]
  end

  def select_list
    @select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow members to view dependency insights.",
        value: "no_policy",
        selected: business_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always allow members to view dependency insights.",
        value: "enabled",
        selected: business_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never allow members to view dependency insights.",
        value: "disabled",
        selected: business_value == "disabled",
      },
    ]
  end

  def business_value
    if !business.members_can_view_dependency_insights_policy?
      "no_policy"
    elsif business.members_can_view_dependency_insights?
      "enabled"
    else
      "disabled"
    end
  end

  def button_text
    selected_option[:heading]
  end

  def selected_option
    select_list.find { |s| s[:selected] }
  end

  def orgs
    orgs = Organization.
      includes(business_membership: [:business]).
      where(business_organization_memberships: { business_id: business.id }).
      order(login: :asc)

    # Tap :to_a method of paginated collection to trigger eager loading
    # to avoid multiple queries in the component.
    orgs.paginate(page: @page, per_page: PAGE_SIZE).tap(&:to_a)
  end
end
