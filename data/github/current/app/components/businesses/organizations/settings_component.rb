# typed: true
# frozen_string_literal: true

class Businesses::Organizations::SettingsComponent < ApplicationComponent
  attr_reader :business, :setting

  def initialize(business:, setting:)
    @business = business
    @setting = setting
  end

  private

  def render?
    @business.present? && partial_for_setting.present?
  end

  def partial_for_setting
    case setting
    when "default_repository_permission"
      "businesses/organizations/settings/default_repository_permission"
    when "repository_creation"
      "businesses/organizations/settings/repository_creation"
    when "allow_private_repository_forking"
      "businesses/organizations/settings/allow_private_repository_forking"
    when "members_can_invite_collaborators"
      "businesses/organizations/settings/members_can_invite_collaborators"
    when "members_can_change_project_visibility"
      "businesses/organizations/settings/members_can_change_project_visibility"
    when "members_can_change_repository_visibility"
      "businesses/organizations/settings/members_can_change_repository_visibility"
    when "members_can_delete_repositories"
      "businesses/organizations/settings/members_can_delete_repositories"
    when "members_can_delete_issues"
      "businesses/organizations/settings/members_can_delete_issues"
    when "members_can_update_protected_branches"
      "businesses/organizations/settings/members_can_update_protected_branches"
    when "team_discussions"
      "businesses/organizations/settings/team_discussions"
    when "organization_projects"
      "businesses/organizations/settings/organization_projects"
    when "repository_projects"
      "businesses/organizations/settings/repository_projects"
    when "saml_identity_provider"
      "businesses/organizations/settings/saml_identity_provider"
    when "members_can_view_dependency_insights"
      "businesses/organizations/settings/dependency_insights"
    when "restrict_notification_delivery"
      "businesses/organizations/settings/restrict_notification_delivery"
    end
  end
end
