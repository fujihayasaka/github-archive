# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::SecurityTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil, is_org_member:)
    @organization = organization
    @link_classes = link_classes
    @text = "Security"
    @tab_id = "org-header-#{@text.parameterize}-tab"
    @is_org_member = is_org_member
  end

  memoize def url
    security_center_risk_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "shield",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    return false unless @organization.present?
    return false unless ::SecurityCenter::SecurityFeatures.security_center_available?(@organization)
    @is_org_member
  end
end
