# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class ContextTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    context "initialize" do
      test "raises an argument error when no surface or subject_gid is provided" do
        assert_raises ArgumentError  do
          build_command_context(surface: nil, subject: nil)
        end
      end

      test "raises an InvalidError when the surface is not a supported surface" do
        assert_raises SlashCommands::Context::InvalidError  do
          build_command_context(surface: :unsupported_surface, subject: nil)
        end
      end

      test "raises an InvalidError when the subject is not a supported surface" do
        assert_raises SlashCommands::Context::InvalidError  do
          build_command_context(subject: build(:user))
        end
      end
    end

    test "next_page! increments page" do
      context = build_command_context(page_number: 3, surface: :issue)

      assert_difference -> { context.page_number }, 1 do
        context.next_page!
      end
    end

    test "previous_page! increments page" do
      context = build_command_context(page_number: 3, surface: :issue)

      assert_difference -> { context.page_number }, -1 do
        context.previous_page!
      end
    end
  end
end
