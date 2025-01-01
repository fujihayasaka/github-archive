# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::ProjectsTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil)
    @organization = organization
    @link_classes = link_classes
    @text = "Projects"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    projects_path(owner: @organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "table",
      counter_class: "js-profile-project-count",
      link_classes: @link_classes,
      hotkey: "g b",
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? && @organization.organization_projects_enabled?
  end
end
