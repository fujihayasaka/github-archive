# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::PeopleTabComponent < ApplicationComponent
  attr_reader :text, :tab_id

  def initialize(organization:, is_billing_manager:, is_direct_or_team_member:, link_classes: nil)
    @organization = organization
    @is_billing_manager = is_billing_manager
    @is_direct_or_team_member = is_direct_or_team_member
    @link_classes = link_classes
    @text = "People"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    org_people_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "person",
      link_classes: @link_classes,
      counter_class: "js-profile-member-count",
      tab_id: tab_id,
    ))
  end

  memoize def render?
    @organization.present? && !hide_people?
  end

  private

  def hide_people?
    @is_billing_manager && !@is_direct_or_team_member
  end
end
