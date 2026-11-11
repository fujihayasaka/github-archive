# typed: true
# frozen_string_literal: true

class Organizations::Settings::DcoPoliciesComponent < ApplicationComponent

  def initialize(organization:)
    @organization = organization
  end

  def signoff_policy_list
    enable_button = GitHub::Menu::ButtonComponent.new(
      text: "All repositories",
      description: "Require signoff on web-based commits for all repositories in this organization",
      replace_text: "All repositories",
      checked: @organization.dco_signoff_enabled?,
      name: "policy",
      value: "all-repos",
      type: "submit",
    )
    disable_button = GitHub::Menu::ButtonComponent.new(
      text: "No policy",
      description: "Each repository chooses whether to require signoff on web-based commits",
      replace_text: "No policy",
      checked: !@organization.dco_signoff_enabled?,
      name: "policy",
      value: "no-policy",
      type: "submit",
    )

    [enable_button, disable_button]
  end
end
