# typed: true
# frozen_string_literal: true

class Businesses::Settings::MembersComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  def remove_user_accounts_when_removing_last_org_membership_select_list
    [
      {
        heading: "Remain in the enterprise",
        description: "Users stay in the enterprise as unaffiliated users when removed from all organizations.",
        value: "false",
        selected: !business.remove_user_accounts_when_removing_last_org_membership_setting_enabled?,
      },
      {
        heading: "Remove from the enterprise",
        description: "Users are removed from the enterprise when removed from all organizations.",
        value: "true",
        selected: business.remove_user_accounts_when_removing_last_org_membership_setting_enabled?,
      },
    ]
  end

  def remove_user_accounts_when_removing_last_org_membership_button_text
    remove_user_accounts_when_removing_last_org_membership_select_list.find { |s| s[:selected] }[:heading]
  end
end
