# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class AlertsCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    context "alert_type" do
      test "lists all available alert types" do
        command = build_command(SlashCommands::AlertsCommand)

        assert_command_rendered(command) do |items|
          assert SlashCommands::AlertsCommand::ALERT_TYPES.keys.all? { |key| items.any? { |item| item.text == key.to_s.humanize } }
        end
      end
    end

    context "markdown" do
      test "renders markdown for the chosen type" do
        command = build_command(SlashCommands::AlertsCommand,
          page_number: 2,
          data: { alert_type: "tip" }
        )

        codeblock = <<~CODEBLOCK
        > [!TIP]
        > %cursor%
        CODEBLOCK

        assert_command_fill(command, codeblock)
      end

      test "silently handles an unsupported alert_type" do
        command = build_command(SlashCommands::AlertsCommand,
          page_number: 2,
          data: { alert_type: "unsupportedtype" }
        )

        codeblock = <<~CODEBLOCK
        > [!]
        > %cursor%
        CODEBLOCK

        assert_command_fill(command, codeblock)
      end

      test "silently handles an empty alert_type" do
        command = build_command(SlashCommands::AlertsCommand,
          page_number: 2,
          data: {}
        )

        codeblock = <<~CODEBLOCK
        > [!]
        > %cursor%
        CODEBLOCK

        assert_command_fill(command, codeblock)
      end
    end
  end
end
