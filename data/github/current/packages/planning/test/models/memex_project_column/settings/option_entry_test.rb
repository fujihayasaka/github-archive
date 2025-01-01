# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSettingsOptionEntryTest < GitHub::TestCase
  test "allows valid options" do
    valid_options = [
      { name: "✨ golden ✨", color: "GRAY", description: "all that glitters" },
      { name: "pick me!", color: "GRAY", description: "" },
      { name: "foo", color: "GRAY", description: "" },
      { name: "foo", color: "BLUE", description: "fighters" },
      { name: "bar", description: "BLUE" },
      { name: "🚨", color: "GRAY", description: "" },
      { id: "aaaaaaaa", name: "foo", color: "ORANGE", description: "" },
      { id: "", name: "foo", description: ""  }, # assigns an ID if one isn't provided
      { id: nil, name: "foo", description: ""  },
      { name: "baz" } # ideally this would be invalid, and require description and color
    ]

    valid_options.each do |option_entry_args|
      option_entry = MemexProjectColumn::Settings::OptionEntry.new(option_entry_args)
      assert_predicate option_entry, :valid?, "option should have been valid: #{option_entry_args}"
      refute_nil option_entry.id
      refute_nil option_entry.name_html
    end
  end

  test "disallows invalid options" do
    invalid_options_with_error = [
      [{ name: "" }, "Name can't be blank"],
      [{ name: "  " }, "Name can't be blank"],
      [{ name: nil }, "Name can't be blank"],
      [{ name: "x" * (MemexProjectColumn::Settings::OptionEntry::NAME_BYTESIZE_LIMIT + 1) }, "Name is too long (maximum is 256 characters)"],
      [{ name: "foo", color: "not-a-color" }, "Color is not included in the list"],
      [{ id: "invalid", name: "foo", color: "aaa" }, "Id is invalid"],
    ]

    invalid_options_with_error.each do |option_entry_args, error|
      option_entry = MemexProjectColumn::Settings::OptionEntry.new(option_entry_args)
      refute_predicate(
        option_entry, :valid?,
        "option should not have been valid: #{option_entry_args}"
      )
      assert_includes(
        option_entry.errors.full_messages,
        error,
        "could not find correct error for invalid option: #{option_entry_args}"
      )
    end
  end
end
