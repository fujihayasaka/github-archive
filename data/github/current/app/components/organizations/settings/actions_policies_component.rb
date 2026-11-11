# typed: true
# frozen_string_literal: true

class Organizations::Settings::ActionsPoliciesComponent < ApplicationComponent

  def initialize(organization:, can_use_entity_selection: true)
    @organization = organization
    @can_use_entity_selection = can_use_entity_selection
  end

  def render?
    @organization.can_write_organization_actions_settings?(current_user)
  end

  memoize def selected_repos_count
    @organization.actions_allowed_entities.count
  end

  def action_policy_list
    enable_button = GitHub::Menu::ButtonComponent.new(
      text: "All repositories",
      description: "Actions can be run by any repository in the organization",
      replace_text: "All repositories",
      checked: @organization.actions_enabled_for_all_entities?,
      name: "policy",
      value: Configurable::ActionsAccess::ALL_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )
    select_entities_button = GitHub::Menu::ButtonComponent.new(
      text: "Selected repositories",
      description: "Actions can only be run by specifically selected repositories",
      replace_text: "Selected repositories",
      checked: @organization.actions_enabled_for_selected_entities?,
      name: "policy",
      value: Configurable::ActionsAccess::SELECTED_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )
    disable_button = GitHub::Menu::ButtonComponent.new(
      text: "Disabled",
      description: "GitHub Actions is disabled for all repositories in the organization",
      replace_text: "Disabled",
      checked: @organization.actions_disabled?,
      name: "policy",
      value: Configurable::ActionsAccess::NO_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )

    @can_use_entity_selection ? [enable_button, select_entities_button, disable_button] : [enable_button, disable_button]
  end

  private

  memoize def repos
    @organization.visible_repositories_for(current_user)
  end
end
