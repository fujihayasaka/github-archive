# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::SettingsTabComponent < ApplicationComponent
  include IntegrationManagerHelper

  attr_reader :text, :tab_id

  def initialize(organization:, setting_fgps:, link_classes: nil)
    @organization = organization
    @setting_fgps = setting_fgps
    @link_classes = link_classes
    @text = "Settings"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    settings_path
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "gear",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    return false unless @organization.present?
    return false unless @setting_fgps.present?

    if @setting_fgps.values.any?
      return true
    end
    false
  end

  private

  def settings_path
    href = settings_org_profile_path(@organization)
  end
end
