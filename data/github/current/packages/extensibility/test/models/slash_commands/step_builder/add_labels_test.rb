# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::AddLabelsTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("label.yml", <<~YAML)
        ---
        trigger: label
        title: Label
        steps:
        - type: addLabels
          id: myPage
          labels:
          - bug
          - duplicate
      YAML

      add_file_to_commands("some_ok_one_bad.yml", <<~YAML)
        ---
        trigger: some_ok_one_bad
        title: Missing Label
        steps:
        - type: addLabels
          id: myPage
          labels:
          - bug
          - duplicate
          - this one does not exist
      YAML

      add_file_to_commands("bad_label.yml", <<~YAML)
        ---
        trigger: bad_label
        title: Missing Label
        steps:
        - type: addLabels
          id: myPage
          labels:
          - this one does not exist
      YAML

      @issue.repository.labels.create!(name: "bug")
      @issue.repository.labels.create!(name: "duplicate")
    end

    test "labels the issue" do
      command = build_user_defined_command("label", subject: @issue)

      assert_changes -> { @issue.labels.pluck(:name) }, from: [], to: %w[bug duplicate] do
        command.process
      end
    end

    test "returns labelled issue number" do
      command = build_user_defined_command("label", subject: @issue)

      command.process

      expected_data = {
        "labelable" => {
          "number" => 1
        }
      }

      assert_equal command.data["myPage"], expected_data
    end

    test "when one of the labels doesn't exist, it is ignored" do
      command = build_user_defined_command("some_ok_one_bad", subject: @issue)

      assert_changes -> { @issue.labels.pluck(:name) }, from: [], to: %w[bug duplicate] do
        command.process
      end
    end

    test "when none of the labels exist, the operation has no effect" do
      command = build_user_defined_command("bad_label", subject: @issue)

      assert_no_changes -> { @issue.labels.pluck(:name) } do
        command.process
      end
    end
  end
end
