# typed: true
# frozen_string_literal: true

class Site::Header::AddDropdownComponent < ApplicationComponent
  attr_reader :react_global_create_menu, :repository

  delegate :create_menu_props, :organization, to: :props
  delegate :show_issue_create_link?, :show_new_repository_link?, :show_repository_import_link?, to: :props
  delegate :show_new_codespace_link?, :show_new_gist_link?, :user_can_create_organizations?,  to: :props
  delegate :show_org_links?, :show_project_link?, :show_legacy_project_link?, to: :props
  delegate :show_spark_link?, to: :props
  delegate :project_path, :legacy_project_path, to: :props
  delegate :tracking_data_attributes, to: :props
  delegate :gist_root_url, to: :helpers

  def initialize(
    user_can_create_organizations:,
    repository:,
    memex_enabled:,
    react_global_create_menu: false,
    **system_arguments
  )
    @user_can_create_organizations = user_can_create_organizations
    @repository = repository
    @memex_enabled = memex_enabled
    @react_global_create_menu = react_global_create_menu

    system_arguments[:test_selector] = "header-add-dropdown"
    system_arguments[:anchor_align] = :end
    @system_arguments = system_arguments
  end

  private

  memoize def props
    @props ||= Site::Header::AddDropdownComponentProps.new(
      current_user: current_user,
      current_organization: current_organization,
      user_can_create_organizations: @user_can_create_organizations,
      repository: @repository,
      memex_enabled: @memex_enabled,
      show_issue_create_link: user_feature_enabled?(:issues_react_global_add),
    )
  end
end
