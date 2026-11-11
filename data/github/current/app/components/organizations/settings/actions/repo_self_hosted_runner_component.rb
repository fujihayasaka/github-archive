# typed: strict
# frozen_string_literal: true

class Organizations::Settings::Actions::RepoSelfHostedRunnerComponent < ApplicationComponent

  sig { params(entity: Organization, action: String).void }
  def initialize(entity:, action:)
    @organization = entity
    @action = action
  end

  sig { returns(T::Boolean) }
  def render?
    @organization.can_write_organization_runners_and_runner_groups?(current_user)
  end

  sig { returns(Integer) }
  memoize def selected_repos_count
    @organization.repo_self_hosted_runners_allowed_entities.count
  end

  sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
  def runners_policy_values
    enable_button = GitHub::Menu::ButtonComponent.new(
      text: "All repositories",
      description: "Repo-level self-hosted runners can be used by any repository in the organization",
      replace_text: "All repositories",
      checked: @organization.repo_self_hosted_runners_enabled_for_all_entities?,
      name: "policy",
      value: Configurable::ActionsRepoSelfHostedRunners::ALL_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )
    select_entities_button = GitHub::Menu::ButtonComponent.new(
      text: "Selected repositories",
      description: "Repo-level self-hosted runners can be used by specifically selected repositories",
      replace_text: "Selected repositories",
      checked: @organization.repo_self_hosted_runners_enabled_for_selected_entities?,
      name: "policy",
      value: Configurable::ActionsRepoSelfHostedRunners::SELECTED_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )
    disable_button = GitHub::Menu::ButtonComponent.new(
      text: "Disabled",
      description: "Repo-level self-hosted runners are disabled for all repositories in the organization",
      replace_text: "Disabled",
      checked: @organization.repo_self_hosted_runners_disabled?,
      name: "policy",
      value: Configurable::ActionsRepoSelfHostedRunners::NO_ENTITIES,
      disabled: @organization.actions_disabled_by_owner?,
      type: "submit",
    )

    [enable_button, select_entities_button, disable_button]
  end
end
