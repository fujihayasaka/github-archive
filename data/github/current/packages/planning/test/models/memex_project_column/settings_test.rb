# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectColumnSettingsTest < GitHub::TestCase
  test "allows valid options settings" do
    options = MemexProjectColumn::Settings.new(
      :single_select,
      {
        width: "100",
        options: [
          { name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
          { name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
          { name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
        ]
      }
    )
    assert_predicate options, :valid?
  end

  test "allows valid configuration settings" do
    options = MemexProjectColumn::Settings.new(
      :iteration,
      {
        width: "100",
        configuration: {
          start_day: 1,
          duration: 14,
          iterations: [
            {
              title: "Iteration 1",
              start_date: "2021-09-06",
              duration: 14
            },
            {
              title: "Iteration 2",
              start_date: "2021-09-20",
              duration: 14
            }
          ],
          completed_iterations: []
        }
      }
    )
    assert_predicate options, :valid?
  end

  test "throws when passed anything other than a Hash for settings" do
    assert_raises MemexProjectColumn::Settings::InitializationError do
      MemexProjectColumn::Settings.new(:iteration, [1, 2, 3])
    end
  end

  test "throws when passed options settings that is not an array" do
    assert_raises MemexProjectColumn::Settings::InitializationError do
      MemexProjectColumn::Settings.new(:iteration, { options: {} })
    end
  end

  test "throws when passed options settings that is not an array of hashes" do
    assert_raises MemexProjectColumn::Settings::InitializationError do
      MemexProjectColumn::Settings.new(:iteration, { options: [[]] })
    end
  end

  test "throws when passed more than one of option, configuration, or progress_configuration settings" do
    assert_raises MemexProjectColumn::Settings::InitializationError do
      MemexProjectColumn::Settings.new(:iteration, {
        options: [],
        configuration: {}
      })
    end

    assert_raises MemexProjectColumn::Settings::InitializationError do
      MemexProjectColumn::Settings.new(:iteration, {
        configuration: {},
        progress_configuration: {},
      })
    end
  end

  test "disallows invalid settings" do
    invalid_settings_with_error = [
      [:text, { width: MemexProjectColumn::Settings::MIN_WIDTH - 1 }, "Width must be greater than or equal to 1"],
      [:text, { width: MemexProjectColumn::Settings::MAX_WIDTH + 1 }, "Width must be less than or equal to 10000"],
      [:text, { font_weight: "bold" }, "Contains unsupported keys: font_weight"],
      [:text, { options: [{ name: "foo" }] }, "Options key is not supported for text column"],
      [:number, { options: [{ name: "foo" }] }, "Options key is not supported for number column"],
      [:date, { options: [{ name: "foo" }] }, "Options key is not supported for date column"],
      [:title, { options: [{ name: "foo" }] }, "Options key is not supported for title column"],
    ]

    invalid_settings_with_error.each do |data_type, settings, error|
      settings_validator = MemexProjectColumn::Settings.new(data_type, settings)
      refute_predicate settings_validator, :valid?, "settings should not have been valid: #{settings}"
      assert_includes settings_validator.errors.full_messages, error, "could not find correct error for invalid settings: #{settings}"
    end
  end

  context "#add_option" do
    test "allows adding option at the end" do
      new_option_name = "pewter"

      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      )
      settings.add_option(name: new_option_name)

      assert_equal new_option_name, settings.options.serialize.last["name"]
    end

    test "allows adding option at a given position" do
      new_option_name = "pewter"
      new_option_position = 1

      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      )
      settings.add_option(name: new_option_name, color: "BLUE", description: "", position: new_option_position)

      assert_equal new_option_name, settings.options.serialize[new_option_position]["name"]
    end

    test "adds option at the end if the given position is out of bounds" do
      new_option_name = "pewter"
      new_option_position = 10

      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      )
      settings.add_option(name: new_option_name, color: "BLUE", description: "", position: new_option_position)

      assert_equal new_option_name, settings.options.serialize[-1]["name"]
      assert_equal 4, settings.options.serialize.size
    end

  end

  context "#update_option" do
    test "allows updating an option's position" do
      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { id: "aaaaaaaa", name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { id: "bbbbbbbb", name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { id: "cccccccc", name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      )

      settings.update_option("aaaaaaaa", position: 2)
      assert_equal "aaaaaaaa", settings.options.serialize.last["id"]
    end

    test "puts an option at the end if the position is out of bounds" do
      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { id: "aaaaaaaa", name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { id: "bbbbbbbb", name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { id: "cccccccc", name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      )

      settings.update_option("aaaaaaaa", position: 20)
      assert_equal "aaaaaaaa", settings.options.serialize.last["id"]
      assert_equal 3, settings.options.serialize.size
    end

    test "transform an option with an emoji" do
      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { id: "aaaaaaaa", name: ":rocket: test", color: "GRAY", description: ""  },
          ]
        }
      )

      assert_equal 1, settings.options.serialize.size
      assert_equal "aaaaaaaa", settings.options.serialize.last["id"]
      assert_equal ":rocket: test", settings.options.serialize.last["name"]
      assert_equal "🚀 test", settings.options.serialize.last["name_html"]
    end

    test "does not permit XSS with an option" do
      xss_input_name = "&lt;script>alert('XSS')&lt;/script> https://github.com <script>alert('XSS')</script> test"
      settings = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { id: "aaaaaaaa", name: xss_input_name, color: "GRAY", description: "" },
          ]
        }
      )

      assert_equal 1, settings.options.serialize.size
      assert_equal "aaaaaaaa", settings.options.serialize.last["id"]
      assert_equal xss_input_name, settings.options.serialize.last["name"]
      refute_match %r{</?script>}, settings.options.serialize.last["name_html"]
    end
  end

  context "#serialize" do
    test "returns a hash with width settings" do
      serialized = MemexProjectColumn::Settings.new(
        :text,
        {
          width: "100",
        }
      ).serialize
      assert serialized.dig(:width)
      refute serialized.dig(:options)
      refute serialized.dig(:configuration)
    end

    test "returns a hash with serialized options settings" do
      serialized = MemexProjectColumn::Settings.new(
        :single_select,
        {
          width: "100",
          options: [
            { id: "aaaaaaaa", name: "🥇 gold 🥇", color: "YELLOW", description: "FIRST" },
            { id: "bbbbbbbb", name: "🥈 silver 🥈", color: "GRAY", description: "SECOND" },
            { id: "cccccccc", name: "🥉 bronze 🥉", color: "ORANGE", description: "THIRD" },
          ]
        }
      ).serialize
      assert serialized.dig(:width)
      assert serialized.dig(:options)
      refute serialized.dig(:configuration)
    end

    test "returns a hash with serialized configuration settings" do
      serialized = MemexProjectColumn::Settings.new(
        :iteration,
        {
          width: "100",
          configuration: {
            start_day: 1,
            duration: 14,
            iterations: [
              {
                title: "Iteration 1",
                start_date: "2021-09-06",
                duration: 14
              },
              {
                title: "Iteration 2",
                start_date: "2021-09-20",
                duration: 14
              }
            ],
          }
        }
      ).serialize
      assert serialized.dig(:width)
      assert serialized.dig(:configuration)
      refute serialized.dig(:options)
    end
  end
end
