# typed: false
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class ApplicationSlashCommandsTest < GitHub::TestCase
    include DogstatsTestHelpers
    include GitHub::SlashCommandTestHelpers

    class TestCommand < ApplicationSlashCommand
      category :test

      trigger_on name: "test_command", title: "test_command", description: "test_command"

      menu :first_page
      menu :empty_state
      fill :insert_value

      def first_page
        menu(
          :my_item,
          items: [
            Item.new(text: "first item", description: "the first item", value: "first"),
            Item.new(text: "second item", description: "the second item", value: "second"),
            Item.new(text: "third item", description: "the third item", value: "third"),
          ]
        )
      end

      def empty_state
        blankslate "Nothing to see here", description: "Nothing to see here: #{data[:my_item]}"
      end

      def insert_value
        "Selected value: #{data[:my_item]}"
      end
    end

    class NoApplicablePageCommand < ApplicationSlashCommand
      menu :first_page, if: :something?
      fill :insert_value, if: :something?

      def something?
        false
      end
    end

    class TestActionCommand < ApplicationSlashCommand
      menu :confirm_action
      perform_action :noop, reload_suggestions: true

      def confirm_action
        menu(
          :confirm,
          items: [
            Item.new(text: "Confirm", value: "yes"),
            Item.new(text: "Cancel", value: "no")
          ])
      end

      def noop
        nil
      end
    end

    class TestParentSupportedSurfaceCommand < ApplicationSlashCommand
      allowed_surfaces :issue
    end

    class TestChildSupportedSurfaceCommand < ApplicationSlashCommand
      SlashCommands.stub_const(:SUPPORTED_SURFACES, [:issue, :issue_body, :issue_comment]) do
        allowed_surfaces :issue_body
      end
    end

    setup do
      TestCommand.feature_flag(nil)
      TestCommand.allowed_surfaces(*SlashCommands::SUPPORTED_SURFACES)
    end

    context "#surface_enabled?" do
      test "returns true on exact match of top level" do
        assert TestParentSupportedSurfaceCommand.surface_enabled?(:issue)
      end

      test "returns true on exact match of second level" do
        assert TestChildSupportedSurfaceCommand.surface_enabled?(:issue_body)
      end

      test "returns false if surface is different sibling of allowed surface" do
        refute TestChildSupportedSurfaceCommand.surface_enabled?(:issue_comment)
      end
    end

    context "#enabled?" do
      context "when allowed_surfaces is nil" do
        test "returns true when no feature flag is defined" do
          TestCommand.feature_flag(nil)
          assert TestCommand.enabled?(build_command_context(surface: :issue))
        end

        test "returns false when feature flag is globally disabled" do
          TestCommand.feature_flag(:my_test_feature)
          disable_feature_flag(:my_test_feature)
          refute TestCommand.enabled?(build_command_context(surface: :issue))
        end

        test "returns false when feature flag is disabled for the user" do
          TestCommand.feature_flag(:my_test_feature)
          user = create :user
          disable_feature_flag(:my_test_feature, user)
          refute TestCommand.enabled?(build_command_context(current_user: user, surface: :issue))
        end

        test "returns true when the feature flag is globally enabled" do
          TestCommand.feature_flag(:my_test_feature)
          enable_feature_flag(:my_test_feature)
          assert TestCommand.enabled?(build_command_context(surface: :issue))
        end

        test "returns true when the feature flag is enabled for the user" do
          TestCommand.feature_flag(:my_test_feature)
          user = create :user
          enable_feature_flag(:my_test_feature, user)
          assert TestCommand.enabled?(build_command_context(current_user: user, surface: :issue))
        end
      end

      context "when feature_flag is nil" do
        test "returns true when no allowed_surfaces are defined" do
          assert TestCommand.enabled?(build_command_context(surface: :issue))
        end

        test "returns false when the context's surface doesn't match one of the allowed_surfaces" do
          TestCommand.allowed_surfaces(:pull_request, :issue)
          refute TestCommand.enabled?(build_command_context(surface: :discussion))
        end

        test "returns true when the context's surface does match one of the allowed_surfaces" do
          TestCommand.allowed_surfaces(:pull_request, :issue)
          assert TestCommand.enabled?(build_command_context(surface: :issue))
        end
      end
    end

    context "#allowed_surfaces" do
      test "raises a ArgumentError when given an unsupported surface" do
        assert_raises ArgumentError do
          TestCommand.allowed_surfaces(:invalid_surface)
        end
      end

      test "doesn't raise when given a supported surface" do
        assert_nothing_raised do
          TestCommand.allowed_surfaces(:issue)
        end
      end
    end

    context "#category" do
      test "sets category" do
        assert_equal :test, TestCommand._category
      end

      test "default category is inherited" do
        command_subclass = Class.new(TestCommand)
        assert_equal :default, command_subclass._category
      end
    end

    context "#flash" do
      test "returns footer with flash message when set" do
        command = build_command do
          fill do |command|
            command.flash.info = "Hey, something happened"

            ""
          end
        end

        command.process
        assert_equal "Hey, something happened", command.flash.info
        refute_nil command.footer
      end

      test "has no footer when flash message isn't set" do
        command = build_command do
          fill do
            ""
          end
        end

        command.process
        assert_nil command.footer
      end
    end

    test "sends timing metric that includes trigger and page" do
      command = build_command(TestCommand, trigger_name: "test_command", trigger_title: "test command")
      command.process

      metric = assert_dogstats_timing("slash_commands.process").first
      assert_includes metric.tags, "trigger:test_command"
      assert_includes metric.tags, "class:SlashCommands::ApplicationSlashCommandsTest::TestCommand"
      assert_includes metric.tags, "page:1"
    end

    context "#page" do
      test "raises error when no page applies" do
        command = build_command do
          menu :first_page, if: :something?
          fill :insert_value, if: :something?

          def something?
            false
          end
        end

        assert_raises SlashCommands::ApplicationSlashCommand::PageNotFound do
          command.page
        end
      end

      test "increments page number until applicable page is found" do
        command = build_command do
          menu :first_page, if: :something?
          menu :second_page, if: :something?
          fill :insert_value

          def something?
            false
          end
        end

        assert_changes -> { command.page_number }, from: 1, to: 3 do
          command.page
        end
      end

      test "reloads_suggestions? is true for pages that have reload_suggestions argument" do
        command = build_command(TestActionCommand, page_number: 2)
        assert command.page.reloads_suggestions?
      end

      test "reloads_suggestions? is false for pages that don't have reload_suggestions argument" do
        command = build_command(TestActionCommand, page_number: 1)
        refute command.page.reloads_suggestions?
      end
    end

    context "#process" do
      test "returns a menu for the first page" do
        command = build_command(TestCommand)

        result = command.process

        assert result.is_a?(SlashCommands::MenuComponent)

        assert_equal "first", result.items[0].value
        assert_equal "first item", result.items[0].text
        assert_equal "the first item", result.items[0].description

        assert_equal "second", result.items[1].value
        assert_equal "second item", result.items[1].text
        assert_equal "the second item", result.items[1].description

        assert_equal "third", result.items[2].value
        assert_equal "third item", result.items[2].text
        assert_equal "the third item", result.items[2].description
      end

      test "returns a blankslate for the second page" do
        command = build_command(TestCommand, data: { my_item: "first" }, page_number: 2, trigger_name: "test_command", trigger_title: "test command")
        result = command.process

        assert result.is_a?(SlashCommands::BlankslateComponent)
        assert_equal ["test command"], result.breadcrumbs
        assert_equal "Nothing to see here", result.title
        assert_equal "Nothing to see here: first", result.description
      end

      test "returns a fill command for the third page" do
        command = build_command(TestCommand, data: { my_item: "second" }, page_number: 3)

        assert_equal "Selected value: second", command.process
      end
    end
  end
end
