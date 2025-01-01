# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::InsightsTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil, is_org_member:)
    @organization = organization
    @link_classes = link_classes
    @text = "Insights"
    @tab_id = "org-header-#{@text.parameterize}-tab"
    @is_org_member = is_org_member
  end

  memoize def url
    org_insights_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "graph",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? &&
      @is_org_member &&
      @organization.has_insights_content_available_for?(current_user)
  end
end
