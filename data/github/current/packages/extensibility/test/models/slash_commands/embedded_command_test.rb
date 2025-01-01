# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class EmbeddedCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @user = create(:user)
      @org = create(:organization)
      @repo = create(:private_repository, name: ".github-private", owner: @org)
    end

    setup do
      example_repo(:simple, @repo)
      GitHub.flipper[:embedded_slash_commands].enable
    end

    context "#enabled?" do
      test "enabled for an org owned repo when the flag is enabled" do
        repository = create(:repository, owner: @org)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        assert SlashCommands::EmbeddedCommand.enabled?(context)
      end

      test "disabled for an org owned repo when the flag is disabled" do
        GitHub.flipper[:embedded_slash_commands].disable
        repository = create(:repository, owner: @org)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        refute SlashCommands::EmbeddedCommand.enabled?(context)
      end

      test "disabled for a user owned repo when the flag is enabled" do
        repository = create(:repository, owner: @user)

        context = build_command_context(current_repository: repository, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
        refute SlashCommands::EmbeddedCommand.enabled?(context)
      end
    end

    test "triggers are based on configured commands" do
      commit = @repo.commits.create({ message: "Add test webhooks", committer: @user.owner }) do |files|
        files.add ".github/slash_commands/webhooks/test.yml", <<~YAML
        trigger: test
        title: Test
        description: It's a test
        YAML

        files.add ".github/slash_commands/webhooks/another-test.yml", <<~YAML
        trigger: another-test
        title: Another Test
        description: It's another test
        YAML
      end

      @repo.refs["refs/heads/master"].update(commit, @user.owner)

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::ISSUE_COMMENT_SURFACE)
      triggers = SlashCommands::EmbeddedCommand.triggers(context).map(&:name)

      assert_includes triggers, "test"
      assert_includes triggers, "another-test"
    end

    test "fills command name" do
      command = build_command(SlashCommands::EmbeddedCommand, trigger_name: "test_embedded_command")

      assert_command_fill(command, <<~MARKDOWN)
        /test_embedded_command
      MARKDOWN
    end
  end
end
