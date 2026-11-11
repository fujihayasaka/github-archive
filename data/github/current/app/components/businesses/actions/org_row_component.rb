# typed: true
# frozen_string_literal: true

class Businesses::Actions::OrgRowComponent < ApplicationComponent
  def initialize(business:, organization:, enabled:)
    @business = business
    @organization = organization
    @enabled = enabled
  end

  def enabled?
    !!@enabled
  end

  def enablement_options
    [
      GitHub::Menu::ButtonComponent.new(
        checked: enabled?,
        text: "Enable",
        name: "enablement",
        value: "enabled",
        description: "All repositories may run Actions. This may be overridden by organization administrators.",
        replace_text: "Enabled",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        checked: !enabled?,
        text: "Disable",
        name: "enablement",
        value: "disabled",
        description: "No repositories have permission to run Actions. This cannot be overridden by organization administrators.",
        replace_text: "Disabled",
        type: "submit",
      ),
    ]
  end
end
