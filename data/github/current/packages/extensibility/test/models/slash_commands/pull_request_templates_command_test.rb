# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class PullRequestTemplatesCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user)
    end

    setup do
      example_repo(:simple, @repo)
      GitHub.flipper[:slash_commands_templates_command].enable
    end

    test "is not enabled when no template exists" do
      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::PULL_REQUEST_BODY_SURFACE)
      refute SlashCommands::PullRequestTemplatesCommand.enabled?(context)
    end

    test "is enabled when a .github/pull_request_template.md exists" do
      create_template!(filename: ".github/pull_request_template.md")

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::PULL_REQUEST_BODY_SURFACE)
      assert SlashCommands::PullRequestTemplatesCommand.enabled?(context)
    end

    test "is enabled when a .github/pull_request_template.txt exists" do
      create_template!(filename: ".github/pull_request_template.txt")

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::PULL_REQUEST_BODY_SURFACE)
      assert SlashCommands::PullRequestTemplatesCommand.enabled?(context)
    end

    test "is enabled when a docs/pull_request_template.md exists" do
      create_template!(filename: "docs/pull_request_template.md")

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::PULL_REQUEST_BODY_SURFACE)
      assert SlashCommands::PullRequestTemplatesCommand.enabled?(context)
    end

    test "is enabled when a docs/pull_request_template.txt exists" do
      create_template!(filename: "docs/pull_request_template.txt")

      context = build_command_context(current_repository: @repo, current_user: @user, surface: SlashCommands::PULL_REQUEST_BODY_SURFACE)
      assert SlashCommands::PullRequestTemplatesCommand.enabled?(context)
    end

    private

    def create_template!(filename:)
      commit = @repo.commits.create({ message: "Add template", committer: @repo.owner }) do |files|
        files.add filename, "test template"
      end

      @repo.refs["refs/heads/master"].update(commit, @repo.owner)
    end
  end
end
