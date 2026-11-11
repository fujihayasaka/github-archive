# typed: true
# frozen_string_literal: true

class Site::Header::AddDropdownComponent < ApplicationComponent
  attr_reader :repository

  def initialize(
    user_can_create_organizations:,
    repository:,
    memex_enabled:,
    **system_arguments
  )
    @user_can_create_organizations = user_can_create_organizations
    @repository = repository
    @memex_enabled = memex_enabled

    system_arguments[:test_selector] = "header-add-dropdown"
    system_arguments[:anchor_align] = :end
    @system_arguments = system_arguments
  end

  private

  memoize def props
    GlobalNavigation::CreateMenuPayload.new(
      current_user: current_user,
      current_copilot_user: current_copilot_user_v2,
      current_organization: current_organization,
      user_can_create_organizations: @user_can_create_organizations,
      current_repository: @repository,
      memex_enabled: @memex_enabled,
      show_issue_create_link: user_feature_enabled?(:issues_react_global_add),
      source: "react_partial"
    ).payload
  end
end
