# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::CreateIssueTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      add_file_to_commands("issue.yml", <<~YAML)
        ---
        trigger: issue
        title: Issue
        steps:
        - type: createIssue
          id: myPage
          title: |-
            {%- if data.title -%}
              {{ data.title }}
            {%- else -%}
              New issue title
            {%- endif -%}
          body: |-
            {%- if data.body -%}
              {{ data.body }}
            {%- else -%}
              New issue body
            {%- endif -%}
      YAML

      add_file_to_commands("issue_no_title_or_body.yml", <<~YAML)
        ---
        trigger: issue_no_title_or_body
        title: Issue
        steps:
        - type: createIssue
          id: myPage
      YAML
    end

    test "creates an issue with default values" do
      command = build_user_defined_command("issue", surface: :issue)

      assert_difference -> { @repo.issues.count }, 1 do
        command.process
      end

      new_issue = @repo.issues.last

      assert_equal new_issue.title, "New issue title"
      assert_equal new_issue.body, "New issue body"
    end

    test "creates an issue with custom values" do
      command = build_user_defined_command("issue", data: { "title" => "My custom title", "body" => "My custom body" }, surface: :issue)

      assert_difference -> { @repo.issues.count }, 1 do
        command.process
      end

      new_issue = @repo.issues.last

      assert_equal new_issue.title, "My custom title"
      assert_equal new_issue.body, "My custom body"
    end

    test "returns new issue title and body" do
      command = build_user_defined_command("issue", surface: :issue)

      command.process

      new_issue = @repo.issues.last
      expected_data = {
        "number" => new_issue.number,
        "title" => new_issue.title
      }

      assert_equal command.data["myPage"], expected_data
    end

    test "creates an issue, even when title and body is not specified in YAML" do
      command = build_user_defined_command("issue_no_title_or_body", surface: :issue)

      assert_difference -> { @repo.issues.count }, 1 do
        command.process
      end

      new_issue = @repo.issues.last

      assert_equal new_issue.title, "New issue"
      assert_nil new_issue.body
    end
  end
end
