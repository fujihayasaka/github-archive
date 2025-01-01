# typed: false
# frozen_string_literal: true

module SlashCommandsHelper
  def slash_commands_enabled?
    return @slash_commands_enabled if defined? @slash_commands_enabled

    @slash_commands_enabled = SlashCommands.enabled_for?(current_user, current_repository)

    @slash_commands_enabled
  end
end
