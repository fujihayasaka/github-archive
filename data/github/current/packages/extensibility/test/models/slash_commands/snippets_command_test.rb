# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class SnippetsCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @repo = create(:private_repository, name: ".github-private", owner: @org)
    end

    setup do
      example_repo(:simple, @repo)
      enable_feature_flag(:snippet_slash_commands)
    end

    context "#enabled?" do
      test "enabled for an org owned repo when the flag is enabled" do
        repository = create(:private_repository, owner: @org)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        assert SlashCommands::SnippetsCommand.enabled?(context)
      end

      test "disabled for an org owned repo when the flag is disabled" do
        disable_feature_flag(:snippet_slash_commands)
        repository = create(:private_repository, owner: @org)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        refute SlashCommands::SnippetsCommand.enabled?(context)
      end

      test "disabled for a user owned repo when the flag is enabled" do
        repository = create(:private_repository, owner: @user)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        refute SlashCommands::SnippetsCommand.enabled?(context)
      end
    end

    test "triggers are based on configured commands" do
      commit = @repo.commits.create({ message: "Add test webhooks", committer: @user.owner }) do |files|
        files.add "slash_commands/snippets/test.yml", <<~YAML
        trigger: test
        title: Test
        description: It's a test
        surfaces: all
        value: Test
        YAML

        files.add "slash_commands/snippets/another-test.yml", <<~YAML
        trigger: another-test
        title: Another Test
        description: It's another test
        surfaces: all
        value: Another Test
        YAML
      end

      @repo.refs["refs/heads/master"].update(commit, @user.owner)

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
      triggers = SlashCommands::SnippetsCommand.triggers(context).map(&:name)

      assert_includes triggers, "test"
      assert_includes triggers, "another-test"
    end

    test "fills snippet value" do
      commit = @repo.commits.create({ message: "Add test webhooks", committer: @user.owner }) do |files|
        files.add "slash_commands/snippets/test.yml", <<~YAML
        trigger: test
        title: Test
        description: It's a test
        surfaces: all
        value: "**This is a test**"
        YAML
      end

      @repo.refs["refs/heads/master"].update(commit, @user.owner)

      command = build_command(SlashCommands::SnippetsCommand, current_repository: @repo, current_user: @user, trigger_name: "test")

      assert_command_fill(command, "**This is a test**")
    end

    test "fill returns empty value if trigger doesn't match a snippet" do
      command = build_command(SlashCommands::SnippetsCommand, current_repository: @repo, current_user: @user, trigger_name: "test")

      assert_nil command.process
    end
  end
end
