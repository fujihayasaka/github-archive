# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class TasklistCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    test "fills tasklist markdown" do
      command = build_command(SlashCommands::TasklistCommand)

      expected = ActiveSupport::SafeBuffer.new <<~MARKDOWN
      ```[tasklist]
      ### Tasks
      - [ ] %cursor%
      ```
      MARKDOWN

      assert_command_fill(command, expected)
    end

    test "enabled? returns false if flag not enabled" do
      GitHub.flipper[:tasklist_block].disable
      context = build_command_context(surface: SlashCommands::ISSUE_BODY_SURFACE)
      refute SlashCommands::TasklistCommand.enabled?(context)
    end

    test "enabled? returns true if flag is enabled" do
      GitHub.flipper[:tasklist_block].enable
      context = build_command_context(surface: SlashCommands::ISSUE_BODY_SURFACE)
      assert SlashCommands::TasklistCommand.enabled?(context)
    end
  end
end
