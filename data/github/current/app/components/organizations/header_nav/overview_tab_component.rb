# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::OverviewTabComponent < ApplicationComponent
  OVERVIEW_TAB_TEXT = "Overview"
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil)
    @organization = organization
    @link_classes = link_classes
    @text = OVERVIEW_TAB_TEXT
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    user_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "home",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  def render?
    @render if defined?(@render)
    @render = @organization.present?
  end
end
