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
      disable_feature_flag(:tasklist_block)
      context = build_command_context(surface: SlashCommands::ISSUE_BODY_SURFACE)
      refute SlashCommands::TasklistCommand.enabled?(context)
    end

    test "enabled? returns true if flag is enabled" do
      enable_feature_flag(:tasklist_block)
      context = build_command_context(surface: SlashCommands::ISSUE_BODY_SURFACE)
      assert SlashCommands::TasklistCommand.enabled?(context)
    end
  end
end
