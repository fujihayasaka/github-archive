# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSettingsOptionsTest < GitHub::TestCase
  test "allows valid options" do
    options = MemexProjectColumn::Settings::Options.new(
      [
        { name: "🥇 gold 🥇", color: "YELLOW", description: "first" },
        { name: "🥈 silver 🥈", color: "GRAY", description: "second" },
        { name: "🥉 bronze 🥉", color: "ORANGE", description: "third" },
        { name: "🥈", color: "GRAY", description: "" },
      ]
    )
    assert_predicate options, :valid?
  end

  test "disallows invalid options" do
    options = MemexProjectColumn::Settings::Options.new(
      [
        { name: "🥇 gold 🥇", color: "YELLOW", description: "first" },
        { name: "" }, # Invalid, it's empty.
        { name: "🥉 bronze 🥉", color: "ORANGE", description: "third" },
      ]
    )
    refute_predicate options, :valid?
    assert_includes options.errors.full_messages, "Option name can't be blank"
  end

  test "allows duplicate option names" do
    options = MemexProjectColumn::Settings::Options.new(
      [
        { name: "one", color: "YELLOW", description: "first" },
        { name: "one", color: "GRAY", description: "second" },
        { name: "two", color: "ORANGE", description: "third" },
      ]
    )
    assert_predicate options, :valid?
  end

  test "disallows duplicate option ids" do
    MemexProjectColumn::Settings::OptionEntry.stubs(:generate_id).returns("non-unique-id")

    options = MemexProjectColumn::Settings::Options.new(
      [
        { name: "one" },
        { name: "two" },
        { name: "three" },
      ]
    )

    assert options.serialize.all? { |o| o["id"] == "non-unique-id" }
    refute_predicate options, :valid?
    assert_includes options.errors.full_messages, "Option id must be unique"
  end

  test "disallows a total number of options that is above the accepted limit" do
    MemexProjectColumn::Settings::Options.stub_const(:OPTION_LIMIT, 2) do
      options = MemexProjectColumn::Settings::Options.new(
        [
          { name: "one" },
          { name: "two" },
          { name: "three" },
        ]
      )

      refute_predicate options, :valid?
      assert_includes options.errors.full_messages, "Options cannot contain more than 2 entries"
    end
  end

  test "trims whitespace in option names" do
    new_option_name = "three"
    options = MemexProjectColumn::Settings::Options.new(
      [
        { name: "one", color: "YELLOW", description: "fist" },
        { name: "two", color: "GRAY", description: "second" },
        { name: " three ", color: "ORANGE", description: "third" },
      ]
    )
    assert_predicate options, :valid?
    assert_equal new_option_name, options.serialize[-1]["name"]
  end
end
