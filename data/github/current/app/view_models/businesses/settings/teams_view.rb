# typed: true
# frozen_string_literal: true

class Businesses::Settings::TeamsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :params

  def initialize(**args)
    super(args)
    @business = args[:business]
  end

  def form_path
    urls.update_team_discussions_allowed_enterprise_path(business)
  end

  def select_list
    @select_list ||= [
      {
        heading: "No policy",
        description: "Organizations choose whether to allow members to start team discussions.",
        value: "no_policy",
        selected: business_value == "no_policy",
      },
      {
        heading: "Enabled",
        description: "Organizations always allow members to start team discussions.",
        value: "enabled",
        selected: business_value == "enabled",
      },
      {
        heading: "Disabled",
        description: "Organizations never allow members to start team discussions.",
        value: "disabled",
        selected: business_value == "disabled",
      },
    ]
  end

  def business_value
    if !business.team_discussions_policy?
      "no_policy"
    elsif business.team_discussions_allowed?
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

  def team_discussions_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "team_discussions")
  end
end
