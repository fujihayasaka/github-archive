# typed: strict
# frozen_string_literal: true

class Organizations::Settings::Actions::DebuggerPolicyComponent < ApplicationComponent
  sig { params(entity: Organization, action: String).void }
  def initialize(entity:, action:)
    @organization = entity
    @action = action
  end

  sig { returns(T::Boolean) }
  def render?
    @organization.can_write_organization_actions_settings?(current_user) &&
      Actions::DebuggerPolicyConfig.new(@organization).feature_flag_enabled?
  end

  sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
  def debugger_policy_values
    config = Actions::DebuggerPolicyConfig.new(@organization)
    disabled = config.disabled_by_owner?

    enable_button = GitHub::Menu::ButtonComponent.new(
      text: "All repositories",
      description: "The job debugger can be used in any repository in the organization",
      replace_text: "All repositories",
      checked: config.enabled_for_all_entities?,
      name: "policy",
      value: Actions::DebuggerPolicyConfig::ALL_ENTITIES,
      disabled: disabled,
      type: "submit",
    )
    select_entities_button = GitHub::Menu::ButtonComponent.new(
      text: "Selected repositories",
      description: "The job debugger can be used in specifically selected repositories",
      replace_text: "Selected repositories",
      checked: config.enabled_for_selected_entities?,
      name: "policy",
      value: Actions::DebuggerPolicyConfig::SELECTED_ENTITIES,
      disabled: disabled,
      type: "submit",
    )
    disable_button = GitHub::Menu::ButtonComponent.new(
      text: "Disabled",
      description: "The job debugger is disabled for all repositories in the organization",
      replace_text: "Disabled",
      checked: config.disabled?,
      name: "policy",
      value: Actions::DebuggerPolicyConfig::NO_ENTITIES,
      disabled: disabled,
      type: "submit",
    )

    [enable_button, select_entities_button, disable_button]
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def repos_picker_props
    {
      orgName: @organization.display_login,
      selectedRepos: selected_repos_props,
      inputName: "enable[]",
      autoSubmitForm: true,
    }
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def selected_repos_props
    owner_login = @organization.display_login
    config = Actions::DebuggerPolicyConfig.new(@organization)
    selected_repo_ids = config.allowed_entity_ids
    selected_repos = @organization.repositories.where(id: selected_repo_ids)

    selected_repos.map do |repo|
      {
        id: repo.id,
        nodeId: repo.global_relay_id,
        name: repo.name,
        ownerLogin: owner_login,
        visibility: repo.visibility,
      }
    end
  end
end
