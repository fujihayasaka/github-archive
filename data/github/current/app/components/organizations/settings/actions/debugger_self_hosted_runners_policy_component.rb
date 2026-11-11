# typed: strict
# frozen_string_literal: true

class Organizations::Settings::Actions::DebuggerSelfHostedRunnersPolicyComponent < ApplicationComponent
  sig { params(entity: Organization, action: String).void }
  def initialize(entity:, action:)
    @organization = entity
    @action = action
  end

  sig { returns(T::Boolean) }
  def render?
    @organization.can_write_organization_actions_settings?(current_user) &&
      Actions::DebuggerSelfHostedRunnersPolicyConfig.new(@organization).feature_flag_enabled?
  end

  sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
  def policy_values
    config = Actions::DebuggerSelfHostedRunnersPolicyConfig.new(@organization)
    disallowed_by_owner = config.disallowed_by_owner?

    [
      GitHub::Menu::ButtonComponent.new(
        text: "Allowed",
        description: "Allow live debugging on self-hosted runners",
        replace_text: "Allowed",
        checked: config.local_allowed?,
        name: "enabled",
        value: "true",
        disabled: disallowed_by_owner,
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        text: "Not allowed",
        description: "Do not allow live debugging on self-hosted runners",
        replace_text: "Not allowed",
        checked: !config.local_allowed?,
        name: "enabled",
        value: "false",
        disabled: disallowed_by_owner,
        type: "submit",
      ),
    ]
  end
end
