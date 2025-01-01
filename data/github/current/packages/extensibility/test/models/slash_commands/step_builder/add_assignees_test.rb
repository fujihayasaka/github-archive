# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::AddAssigneesTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("assign.yml", <<~YAML)
        ---
        trigger: assign
        title: Assign
        steps:
        - type: addAssignees
          id: myPage
          assignees:
          - #{@owner.login}
      YAML
    end

    test "assigns users to issue" do
      command = build_user_defined_command("assign", subject: @issue)

      assert_changes -> { @issue.assignees.reload.to_a }, from: [], to: [@owner] do
        command.process
      end
    end

    test "returns new comment global relay id" do
      command = build_user_defined_command("assign", subject: @issue)

      command.process

      expected_data = {
        "data" => {
          "addAssigneesToAssignable" => {
            "assignable" => {
              "number" => @issue.number
            }
          }
        }
      }

      assert_equal command.data["myPage"], expected_data
    end

    test "fails when user isn't allowed to be assigned" do
      other_user = create(:user)
      command = build_user_defined_command("assign", current_user: other_user, subject: @issue)

      command.process

      assert_same_elements @issue.assignees.reload, []
      assert_includes command.flash.error, "Problem while executing step 1 (myPage)"
    end
  end
end
