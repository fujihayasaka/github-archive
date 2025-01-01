# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Commands
    class DisplayAsTestCommand < ApplicationCommand
      display_as "Test Command", name: "test_command", icon: "pencil", hint: "Display As Test Command", priority: 15
    end

    class MultipleDisplayAsTestCommand < ApplicationCommand
      display_as "Test Command First"
      display_as "Test Command Second"
    end

    class ApplicationCommandTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @user = create(:user, :verified)
        @context = build_context(current_user: @user)
      end

      context "#subject" do
        test "returns context.scope.object" do
          context = build_context(current_user: @user, scope: build(:issue))
          command = ApplicationCommand.new(context)

          assert_equal command.scoped_object, context.scope.object
        end

        test "returns nil when scope is not defined" do
          context = build_context(current_user: @user, subject: build(:issue))
          command = ApplicationCommand.new(context)

          assert_nil command.scoped_object
        end
      end

      context "#to_result" do
        test "converts a display to a result object" do
          command = DisplayAsTestCommand.new(@context)
          result = command.to_result.as_json

          assert_equal result[:title], "Test Command"
          assert_equal result[:action][:id], "test_command"
          assert_equal result[:icon], Icons::Octicon.new(name: "pencil")
          assert_equal result[:hint], "Display As Test Command"
          assert_equal result[:priority], 15
        end

        test "uses the last display_as if multiple are provided" do
          command = MultipleDisplayAsTestCommand.new(@context)
          result = command.to_result.as_json

          assert_equal result[:title], "Test Command Second"
        end
      end
    end
  end
end
