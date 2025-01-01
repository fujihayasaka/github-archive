# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class SavedRepliesCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    test "displays blankslates when user has no saved replies" do
      command = build_command(SlashCommands::SavedRepliesCommand)
      assert_command_blankslate(command, title: "No saved replies", description: /create one/)
    end

    test "displays saved replies" do
      user = create(:user)
      replies = [
        create(:saved_reply, user: user, title: "Hot dogs", body: "Body text"),
        create(:saved_reply, user: user, title: "Hamburgers", body: "Body text 2")
      ]

      command = build_command(SlashCommands::SavedRepliesCommand, current_user: user)

      assert_command_rendered(command, count: 2) do |menu_items|
        assert_same_elements replies.map(&:title), menu_items.map(&:text)
        assert_same_elements replies.map(&:body), menu_items.map(&:value)
      end
    end

    test "doesn't display more than the maximum replies" do
      max_replies_displayed = 5

      SlashCommands::SavedRepliesCommand.stub_const(:SAVED_REPLIES_LIMIT, max_replies_displayed) do
        user = create(:user)

        replies = 8.times.map do |i|
          create(:saved_reply, user: user, title: "reply #{i}", body: "Body text {i}")
        end

        command = build_command(SlashCommands::SavedRepliesCommand, current_user: user)
        assert_command_rendered(command, count: max_replies_displayed)
      end
    end

    test "returns saved reply content for given saved reply ID" do
      user = create(:user)
      command = build_command(SlashCommands::SavedRepliesCommand, current_user: user, page_number: 2, data: { reply: "Body text" })
      assert_command_fill(command, "Body text")
    end
  end
end
