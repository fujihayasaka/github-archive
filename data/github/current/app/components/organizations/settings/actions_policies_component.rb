# typed: true
# frozen_string_literal: true

class Organizations::Settings::ActionsPoliciesComponent < ApplicationComponent
  # Number of selected repositories to fully hydrate for the React picker.
  HOLLOW_REPOS_THRESHOLD = 500

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

  def repos_picker_props
    {
      orgName: @organization.display_login,
      selectedRepos: selected_repos_props,
      inputName: "enable[]",
      autoSubmitForm: true,
    }
  end

  def selected_repos_props
    owner_login = @organization.display_login
    selected_repo_ids = Array(@organization.actions_allowed_entities)

    # The repo picker only shows 500 options but was trying to load all of them in the background, which timed out,
    # so we only provide "hollow" objects consisting of id so they can be lazy loaded when filtering
    if selected_repo_ids.size > HOLLOW_REPOS_THRESHOLD
      full_repo_ids = selected_repo_ids.first(HOLLOW_REPOS_THRESHOLD)
      hollow_repo_ids = selected_repo_ids.drop(HOLLOW_REPOS_THRESHOLD)
    else
      full_repo_ids = selected_repo_ids
      hollow_repo_ids = []
    end

    selected_repos = Repositories.domain.by_ids(full_repo_ids, include_internal_repository: true)

    full_props = selected_repos.map do |repo|
      {
        id: repo.id,
        nodeId: repo.global_relay_id,
        name: repo.name,
        ownerLogin: owner_login,
        visibility: T.cast(repo, Repository).visibility # rubocop:todo GitHub/AvoidCast
      }
    end

    hollow_props = hollow_repo_ids.map do |id|
      {
        id: id,
        nodeId: Platform::Helpers::NodeIdentification.to_global_id("Repository", id),
      }
    end

    full_props + hollow_props
  end

  private

  memoize def repos
    @organization.visible_repositories_for(current_user)
  end
end
