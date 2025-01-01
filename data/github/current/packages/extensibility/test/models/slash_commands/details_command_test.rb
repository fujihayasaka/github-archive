# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class DetailsCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    test "fills detail markup" do
      command = build_command(SlashCommands::DetailsCommand)

      assert_command_fill(command, <<~MARKDOWN)
        <details><summary>Details</summary>
        <p>

        %cursor%

        </p>
        </details>
      MARKDOWN
    end
  end
end
