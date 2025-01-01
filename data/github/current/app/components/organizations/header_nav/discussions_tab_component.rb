# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::DiscussionsTabComponent < ApplicationComponent
  include ApplicationComponent::Rescuable
  rescue_from_database_errors with: :nothing

  attr_reader :text, :tab_id

  def initialize(organization:, link_classes: nil)
    @organization = organization
    @link_classes = link_classes
    @text = "Discussions"
    @tab_id = "org-header-#{@text.parameterize}-tab"
  end

  memoize def url
    org_discussions_path(@organization)
  end

  def call
    render(Organizations::HeaderNav::TabComponent.new(
      url: url,
      text: text,
      icon: "comment-discussion",
      link_classes: @link_classes,
      test_selector: "discussions-tab",
      tab_id: tab_id,
    ))
  end

  memoize def render?
    return false unless GitHub.discussions_available_on_platform?
    return false unless @organization.present?
    target_repo.present? && current_user_can_read_target_repo?
  end

  memoize def target_repo
    return nil unless @organization.present?
    @organization.discussion_repository&.repository
  end

  memoize def current_user_can_read_target_repo?
    target_repo&.readable_by?(current_user)
  end
end
