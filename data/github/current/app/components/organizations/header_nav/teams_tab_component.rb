# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::TeamsTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, is_direct_or_team_member:, link_classes: nil)
    @organization = organization
    @is_direct_or_team_member = is_direct_or_team_member
    @link_classes = link_classes
    @text = "Teams"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    teams_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "people",
      counter_class: "js-profile-team-count",
      link_classes: @link_classes,
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? && @is_direct_or_team_member
  end
end
