# typed: true
# frozen_string_literal: true

class Businesses::Actions::OrgBulkEnableComponent < ApplicationComponent
  attr_reader :organization_ids

  def initialize(business:, organizations:)
    @business = business
    @organization_ids = organizations.pluck(:id)
  end

  def form_params
    {
      organization_ids: organization_ids,
      page: helpers.current_page,
      q: params["q"],
    }
  end

  def enablement_options
    [
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Enabled",
        name: "enablement",
        value: "enabled",
        description: "All repositories may run Actions. This may be overridden by organization administrators.",
        replace_text: "Enabled",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: false,
        text: "Disabled",
        name: "enablement",
        value: "disabled",
        description: "No repositories have permission to run Actions. This cannot be overridden by organization administrators.",
        replace_text: "Disabled",
        type: "submit",
      ),
    ]
  end
end
