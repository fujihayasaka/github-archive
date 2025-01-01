# typed: true
# frozen_string_literal: true

class Businesses::Settings::OrganizationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :params

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def form_path
    urls.update_members_can_view_dependency_insights_enterprise_path(business)
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

  def input_value
    selected_option[:value]
  end

  def selected_option
    select_list.find { |s| s[:selected] }
  end

  def dependency_insights_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "members_can_view_dependency_insights")
  end
end
