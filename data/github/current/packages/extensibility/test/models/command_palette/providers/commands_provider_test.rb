# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class ProviderTestCommand < CommandPalette::Commands::ApplicationCommand
      scope_type "Issue"
      display_as "Provider Test"

      def enabled?
        true
      end
    end

    class CommandsProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:verified_user, login: "ben")
        @user_repo = create(:repository, owner: @user, has_discussions: true, from_example: :pull_request_source)
      end

      test "element configuration" do
        assert_equal "commands", CommandsProvider.type
        assert_equal 0, CommandsProvider.debounce
        assert_equal 0, CommandsProvider.fetch_modes.count
      end

      context "pseudo commands" do
        test "returns link to create new repository" do
          items = build_provider.search("")

          assert_includes items.map(&:title), "New repository"
        end

        test "every scope returns items for the global commands group" do
          org = create(:organization)
          repo = create(:repository)
          issue = create(:issue)

          items = build_provider.search("")
          assert_includes items.map(&:group), :global_commands

          items = build_provider(scope: @user).search("")
          assert_includes items.map(&:group), :global_commands

          items = build_provider(scope: org).search("")
          assert_includes items.map(&:group), :global_commands

          items = build_provider(scope: repo).search("")
          assert_includes items.map(&:group), :global_commands

          items = build_provider(scope: issue).search("")
          assert_includes items.map(&:group), :global_commands
        end

        test "returns link to create new issue when scoped to repository" do
          unscoped_items = build_provider.search("")
          user_scoped_items = build_provider(scope: @user).search("")
          repo_scoped_items = build_provider(scope: @user_repo).search("")

          refute_includes unscoped_items.map(&:title), "New issue"
          refute_includes user_scoped_items.map(&:title), "New issue"
          assert_includes repo_scoped_items.map(&:title), "New issue"
        end

        test "does not return link to create new issue when repository has issues disabled" do
          @user_repo.update_attribute(:has_issues, false)

          unscoped_items = build_provider.search("")
          user_scoped_items = build_provider(scope: @user).search("")
          repo_scoped_items = build_provider(scope: @user_repo).search("")

          refute_includes unscoped_items.map(&:title), "New issue"
          refute_includes user_scoped_items.map(&:title), "New issue"
          refute_includes repo_scoped_items.map(&:title), "New issue"
        end

        test "returns link to create new discussion when scoped to repository" do
          items = build_provider(scope: @user_repo).search("")
          assert_includes items.map(&:title), "New discussion"
        end

        if GitHub.enterprise?
          test "does not return link to create new organization when organization are disabled" do
            @user_repo.update_attribute(:has_issues, false)

            unscoped_items = build_provider.search("")
            user_scoped_items = build_provider(scope: @user).search("")
            repo_scoped_items = build_provider(scope: @user_repo).search("")

            refute_includes unscoped_items.map(&:title), "New organization"
            refute_includes user_scoped_items.map(&:title), "New organization"
            refute_includes repo_scoped_items.map(&:title), "New organization"
          end
        else
          test "returns link to create new organization when organizations are enabled" do
            unscoped_items = build_provider.search("")
            user_scoped_items = build_provider(scope: @user).search("")
            repo_scoped_items = build_provider(scope: @user_repo).search("")

            assert_includes unscoped_items.map(&:title), "New organization"
            assert_includes user_scoped_items.map(&:title), "New organization"
            assert_includes repo_scoped_items.map(&:title), "New organization"
          end
        end

        test "returns link to create new gist when gists are enabled" do
          unscoped_items = build_provider.search("")
          user_scoped_items = build_provider(scope: @user).search("")
          repo_scoped_items = build_provider(scope: @user_repo).search("")

          assert_includes unscoped_items.map(&:title), "New gist"
          assert_includes user_scoped_items.map(&:title), "New gist"
          assert_includes repo_scoped_items.map(&:title), "New gist"
        end

        test "does not return link to create new gist when gists are disabled" do
          @user_repo.update_attribute(:has_issues, false)

          GitHub.expects(:gist_enabled?).at_least_once.returns(false)

          unscoped_items = build_provider.search("")
          user_scoped_items = build_provider(scope: @user).search("")
          repo_scoped_items = build_provider(scope: @user_repo).search("")

          refute_includes unscoped_items.map(&:title), "New gist"
          refute_includes user_scoped_items.map(&:title), "New gist"
          refute_includes repo_scoped_items.map(&:title), "New gist"
        end
      end

      context "commands" do
        test "returns an empty array if the feature flag is disabled" do
          disable_feature_flag(:command_palette_commands)
          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, [ProviderTestCommand]) do
            assert_empty build_provider(subject: build(:issue)).commands
          end
        end

        test "returns any commands found by the finder when feature flag is enabled" do
          enable_feature_flag(:command_palette_commands)

          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, [ProviderTestCommand]) do
            commands = build_provider(scope: build(:issue)).commands
            assert_includes commands.map(&:title), "Provider Test"
            assert_equal commands.map(&:group).uniq, [:commands]
          end
        end
      end

      def item_titles_for(subject)
        build_provider(subject: subject).search("").map(&:title)
      end

      def build_provider(current_user: @user, subject: nil, scope: nil)
        context = Context.new(current_user: current_user, subject: subject, scope: scope)
        CommandsProvider.new(context)
      end
    end
  end
end
