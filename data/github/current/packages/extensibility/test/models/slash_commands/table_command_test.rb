# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class TableCommandTest < GitHub::TestCase
    include GitHub::SlashCommandTestHelpers

    test "displays 5 columns" do
      command = build_command(SlashCommands::TableCommand)

      assert_command_rendered(command, count: 5) do |menu_items|
        assert_same_elements ["1 column", "2 columns", "3 columns", "4 columns", "5 columns"], menu_items.map(&:text)
        assert_same_elements [1, 2, 3, 4, 5], menu_items.map(&:value)
      end
    end

    test "displays 5 rows" do
      command = build_command(SlashCommands::TableCommand, page_number: 2, data: { value: 3 })

      assert_command_rendered(command, count: 5) do |menu_items|
        assert_same_elements ["1 row", "2 rows", "3 rows", "4 rows", "5 rows"], menu_items.map(&:text)
        assert_same_elements [1, 2, 3, 4, 5], menu_items.map(&:value)
      end
    end

    test "fills item when selected" do
      command = build_command(SlashCommands::TableCommand, page_number: 3, data: { rows: 4, columns: 3 })

      expectation = [
        "| Header | Header | Header |",
        "|--------|--------|--------|",
        "| Cell | Cell | Cell |",
        "| Cell | Cell | Cell |",
        "| Cell | Cell | Cell |",
        "| Cell | Cell | Cell |"
      ].join("\n")
      assert_command_fill(command, expectation)
    end
  end
end
