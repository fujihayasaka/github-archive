# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StepBuilder::FillTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    setup do
      GitHub.flipper[:personal_commands].enable
    end

    test "fills in a template when the command is run" do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello
        title: Hello
        steps:
          - type: fill
            template_path: .github/commands/hello_template.liquid
      YAML
      add_file_to_commands("hello_template.liquid", <<~YAML)
        ---

        <p>Hello there!</p>
      YAML
      command = build_user_defined_command("hello", subject: @issue)

      assert_command_fill(command, "Hello there!")
    end

    test "filled template interpolates template variables" do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello_interpolate
        title: Hello
        steps:
          - type: fill
            template_path: .github/commands/hello_issue_template.liquid
      YAML
      add_file_to_commands("hello_issue_template.liquid", <<~YAML)
        ---

        <p>Hello {{ command.user.login }}!</p>
      YAML
      command = build_user_defined_command("hello_interpolate", subject: @issue)

      assert_command_fill(command, "Hello #{@owner.login}!")
    end

    test "uses config template when specified" do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello_inline
        title: Hello
        steps:
          - type: fill
            template: "Hello {{ command.user.login }}!"
      YAML
      command = build_user_defined_command("hello_inline", subject: @issue)

      assert_command_fill(command, "Hello #{@owner.login}!")
    end

    test "falls back to config template when template file is not found" do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello_not_found
        title: Hello
        steps:
          - type: fill
            template_path: .github/commands/hello_issue_template.liquid
            template: "Hello {{ command.user.login }}!"
      YAML
      command = build_user_defined_command("hello_not_found", subject: @issue)

      assert_command_fill(command, "Hello #{@owner.login}!")
    end

    test "warns user when template isn't found and there's no fallback" do
      add_file_to_commands("hello.yml", <<~YAML)
        ---
        trigger: hello_no_fallback
        title: Hello
        steps:
          - type: fill
            template_path: .github/commands/non_existant_template.liquid
      YAML
      command = build_user_defined_command("hello_no_fallback", subject: @issue)

      assert_command_fill(command, "Template not found")
    end

    test "uses user private repository template path when user command" do
      @dot_github_private_repo_for_user = create(:private_repository, name: ".github-private", owner: @owner, from_example: :simple)
      add_file_to_commands("hello.yml", <<~YAML, repo: @dot_github_private_repo_for_user)
        ---
        trigger: hello_private
        title: Hello
        steps:
          - type: fill
            template_path: .github/commands/hello_template1.liquid
      YAML
      add_file_to_commands("hello_template1.liquid", <<~YAML, repo: @dot_github_private_repo_for_user)
        ---

        <p>Hello there!</p>
      YAML

      command = build_user_defined_command(
        "hello_private",
        source_repository: @dot_github_private_repo_for_user,
        subject: @issue,
      )

      assert_command_fill(command, "Hello there!")
    end
  end
end
