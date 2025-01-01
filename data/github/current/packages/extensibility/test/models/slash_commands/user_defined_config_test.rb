# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class UserDefinedConfigTest < GitHub::TestCase
    include GitHub::UserDefinedCommandTestHelpers

    fixtures do
      @dot_github_private_repo_for_user = create(:private_repository, name: ".github-private", owner: @owner, from_example: :simple)
      add_file_to_commands("personal.yml", <<~YAML, repo: @dot_github_private_repo_for_user)
        trigger: personal
        title: Personal
        steps:
          - type: fill
            template: from personal command
      YAML

      add_file_to_commands("granular_surface.yml", <<~YAML, repo: @dot_github_private_repo_for_user)
        trigger: granular_surface
        title: Granular Surface
        surfaces:
          - issue_comment
        steps:
          - type: fill
            template: from personal command
      YAML

      add_file_to_commands("top_level_surface.yml", <<~YAML, repo: @dot_github_private_repo_for_user)
        trigger: top_level_surface
        title: Top Level Surface
        surfaces:
          - issue
        steps:
          - type: fill
            template: from personal command
      YAML

      @dot_github_private_repo_for_org = create(:private_repository, name: ".github-private", owner: @org, from_example: :simple)
      add_file_to_commands("organization.yml", <<~YAML, repo: @dot_github_private_repo_for_org)
        trigger: organization
        title: Organization
        steps:
          - type: fill
            template: from organization command
      YAML
    end

    setup do
      enable_feature_flag(:personal_commands)
      enable_feature_flag(:organization_commands)
    end

    context ".source_repositories" do
      test "only returns context repository when user and org hasn't created a .github-private repository" do
        other_owner = create(:user, login: "monalisa2")
        other_repo = create(:private_repository, :org_owned, from_example: :simple)
        other_repo.add_member(other_owner, action: :admin)

        context = build_command_context(current_repository: other_repo, current_user: other_owner, surface: :issue)

        assert_equal UserDefinedConfig.source_repositories(context), [other_repo]
      end

      test "includes user's .github-private repository" do
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        assert_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_user
      end

      test "doesn't include user's .github-private repository when feature flag is disabled" do
        disable_feature_flag(:personal_commands)
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_user
      end

      test "doesn't include user's .github-private repository when it is public" do
        @dot_github_private_repo_for_user.toggle_visibility(actor: @owner, visibility: "public")
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_user
      end

      test "doesn't include user's .github-private repository when it has been archived" do
        @dot_github_private_repo_for_user.set_archived
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_user
      end

      test "includes org's .github-private repository" do
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        assert_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_org
      end

      test "doesn't include org's .github-private repository when feature flag is disabled" do
        disable_feature_flag(:organization_commands)
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_org
      end

      test "doesn't include org's .github-private repository when it is public", skip_enterprise: true do
        @dot_github_private_repo_for_org.toggle_visibility(actor: @owner, visibility: "public")
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_org
      end

      test "doesn't include org's .github-private repository when it has been archived" do
        @dot_github_private_repo_for_org.set_archived
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        refute_includes UserDefinedConfig.source_repositories(context), @dot_github_private_repo_for_org
      end
    end

    context ".surfaces" do
      test "returns listed surfaces" do
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        commands = UserDefinedConfig.from_context(context)
        command = commands.find { |command| command.data["trigger"] == "granular_surface" }
        assert_equal ["issue_comment"], command.surfaces
      end

      test "expands nested surfaces" do
        context = build_command_context(current_repository: @repo, current_user: @owner, surface: :issue)

        commands = UserDefinedConfig.from_context(context)
        command = commands.find { |command| command.data["trigger"] == "top_level_surface" }
        assert_equal %w[issue issue_body issue_comment], command.surfaces
      end
    end
  end
end
