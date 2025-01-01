# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class DemosCommandTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers
    include GitHub::SlashCommandTestHelpers

    test "disabled outside of development" do
      context = build_command_context(surface: :issue)

      Rails.stubs(:env).returns("development".inquiry)
      assert SlashCommands::DemosCommand.enabled?(context)

      Rails.stubs(:env).returns("production".inquiry)
      refute SlashCommands::DemosCommand.enabled?(context)
    end

    test "enabled for staff" do
      staff_context = build_command_context(current_user: create(:user, :staff), surface: :issue)
      assert staff_context.current_user.site_admin?
      assert SlashCommands::DemosCommand.enabled?(staff_context)

      context = build_command_context(current_user: create(:user), surface: :issue)
      refute context.current_user.site_admin?
      refute SlashCommands::DemosCommand.enabled?(context)
    end

    test "form actions work" do
      command = build_command(DemosCommand, page_number: 2, data: { demo: "form_actions" })

      render_inline(command)

      assert_selector("[data-test-selector=form-actions] button", text: "Cancel")
      assert_selector("[data-test-selector=form-actions] button[type=submit]", text: "Insert data")
    end
  end
end
