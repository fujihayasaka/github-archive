# typed: true
# frozen_string_literal: true

require "test_helper"

module CommmandPalette
  module Commands
    class TestBasicCommand < CommandPalette::Commands::ApplicationCommand
      display_as "test command"

      def enabled?
        true
      end
    end

    class TestScopeTypeCommand < CommandPalette::Commands::ApplicationCommand
      scope_type "User"
      display_as "scope_type"

      def enabled?
        true
      end
    end

    class TestMultipleScopeTypeCommand < CommandPalette::Commands::ApplicationCommand
      scope_type "Issue", "Repository"
      display_as "multiple_scope_type"

      def enabled?
        true
      end
    end

    class TestEnabledCommand < CommandPalette::Commands::ApplicationCommand
      scope_type "Issue"
      display_as "enabled_test"

      def enabled?
        context.subject.title == "Issue for enabled? test"
      end
    end

    class CommandFinderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      context "#find_commands" do
        test "returns commands matching subject type" do
          issue = build(:issue)
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          commands = [
            TestBasicCommand,
            TestScopeTypeCommand,
            TestMultipleScopeTypeCommand,
            TestEnabledCommand
          ]

          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, commands) do
            found_commands = CommandPalette::Commands::CommandFinder.find_commands(context)
            assert_equal 2, found_commands.count
            assert_equal TestBasicCommand, found_commands[0].class
            assert_equal TestMultipleScopeTypeCommand, found_commands[1].class
          end
        end

        test "commands where enabled? returns true" do
          issue = build(:issue, title: "Issue for enabled? test")
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          commands = [
            TestBasicCommand,
            TestScopeTypeCommand,
            TestMultipleScopeTypeCommand,
            TestEnabledCommand
          ]

          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, commands) do
            found_commands = CommandPalette::Commands::CommandFinder.find_commands(context)
            assert_equal 3, found_commands.count
            assert_equal TestBasicCommand, found_commands[0].class
            assert_equal TestMultipleScopeTypeCommand, found_commands[1].class
            assert_equal TestEnabledCommand, found_commands[2].class
          end
        end
      end

      context "#find_command" do
        test "finds a command based on display" do
          issue = build(:issue)
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          commands = [
            TestBasicCommand,
            TestScopeTypeCommand,
            TestMultipleScopeTypeCommand
          ]

          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, commands) do
            found_command = CommandPalette::Commands::CommandFinder.find_command(context, "multiple_scope_type")
            assert_equal TestMultipleScopeTypeCommand, found_command.class
          end
        end

        test "doesn't return a command if scope_type doesn't match" do
          issue = build(:issue)
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, [TestScopeTypeCommand]) do
            assert_nil CommandPalette::Commands::CommandFinder.find_command(context, "scope_type")
          end
        end

        test "doesn't return a command if enabled? doesn't return true" do
          issue = build(:issue)
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, [TestEnabledCommand]) do
            assert_nil CommandPalette::Commands::CommandFinder.find_command(context, "enabled_test")
          end
        end

        test "returns a command if enabled? returns true" do
          issue = build(:issue, title: "Issue for enabled? test")
          context = build_context(current_user: build(:user), scope: issue, subject: issue)
          CommandPalette::Commands::CommandFinder.stub_const(:COMMANDS, [TestEnabledCommand]) do
            found_command = CommandPalette::Commands::CommandFinder.find_command(context, "enabled_test")
            assert_equal TestEnabledCommand, found_command.class
          end
        end
      end
    end
  end
end
