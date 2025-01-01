# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSettingsTest < GitHub::TestCase
  test "get retrieves attributes from the underlying UserSettings" do
    user_settings = build(:user_settings, settings: { tab_size: 4 })
    assert_equal 4, user_settings.get(:tab_size)
  end

  test "get raises an ArgumentError if the key isn't an attribute of User:SettingsCollection" do
    user_settings = build(:user_settings, settings: { tab_size: 4 })
    assert_raises(ArgumentError) do
      user_settings.get(:ahoy)
    end
  end

  test "set!(attr_name) will update the record if the new value is valid" do
    user_settings = create(:user_settings, settings: { tab_size: 4 })
    assert_equal user_settings.get(:tab_size), 4
    user_settings.set!(:tab_size, 12)
    assert_equal 12, user_settings.reload.get(:tab_size)
  end

  test "stores settings as an empty json object by default" do
    user_settings = create(:user_settings)

    # The default value is an empty json object
    assert_equal "{}", user_settings.read_attribute_before_type_cast(:settings)
    assert_equal 8, user_settings.get(:tab_size)
  end

  test "set! will remove attr_name from the settings if it has the default value" do
    user_settings = create(:user_settings)

    # show that we serialize a non-default value
    user_settings.set!(:tab_size, 12)
    assert_equal "{\"tab_size\": 12}", user_settings.read_attribute_before_type_cast(:settings)

    # show that setting tab size back to the default removes the attribute
    user_settings.set!(:tab_size, 8)
    assert_equal "{}", user_settings.read_attribute_before_type_cast(:settings)
  end

  test "set! persists user_profile_lists_sorting_strategy" do
    user_settings = create(:user_settings)

    user_settings.set!(:user_profile_lists_sorting_strategy, "created_at.asc")
    assert_equal "created_at.asc", user_settings.reload.get(:user_profile_lists_sorting_strategy)

    user_settings.set!(:user_profile_lists_sorting_strategy, "created_at.desc")
    assert_equal "created_at.desc", user_settings.reload.get(:user_profile_lists_sorting_strategy)
  end

  test "set! persists link_underlines" do
    user_settings = create(:user_settings)
    initial_value = user_settings.get(:link_underlines)

    user_settings.set!(:link_underlines, !initial_value)
    assert_equal !initial_value, user_settings.reload.get(:link_underlines)
  end

  test "set! will raise a SettingsCollection::InvalidUpdate exception if the new value is not valid" do
    user_settings = create(:user_settings)
    err = assert_raises(SettingsCollection::InvalidUpdate) do
      user_settings.set!(:tab_size, -1)
    end

    assert_equal "tab_size: Tab size is not included in the list", err.message
  end

  test "set! will raise an ArgumentError if the key is not an attribute on UserSettings" do
    user_settings = create(:user_settings)
    assert_raises(ArgumentError) do
      user_settings.set!(:ahoy, -1)
    end
  end
end

class UserSettingsValidationTest < GitHub::TestCase
  attr_reader :record

  def build(values)
    UserSettings.new(settings: values)
  end

  def refute_valid(setting_payload, expected_validation_message)
    settings = build(setting_payload)
    refute_predicate settings, :valid?
    errors = settings.errors.messages
    assert_includes errors, :settings
    assert_includes errors[:settings], expected_validation_message
  end

  def assert_valid(setting_payload)
    settings = build(setting_payload)
    assert settings.valid?,
      "expected valid record from input #{setting_payload.inspect}, got error: #{settings.errors.full_messages.to_sentence.inspect}"
  end

  def assert_default(values)
    settings_collection = UserSettings.new.settings

    values.each do |preference, expected_default|
      actual = settings_collection.send(preference)
      assert expected_default == actual, "expected default for #{preference.inspect} to be #{expected_default}, got #{actual}"
    end
  end

  context "validation" do
    context "tab_size" do
      test "defaults to 8" do
        assert_default(tab_size: 8)
      end

      test "tab_size must be in a fixed range of values" do
        refute_valid({ tab_size: -1 }, "is invalid: Tab size is not included in the list")
        refute_valid({ tab_size: 0 }, "is invalid: Tab size is not included in the list")
        assert_valid(tab_size: 3)
      end
    end

    context "keyboard_shortcuts_preference" do
      test "defaults to 'all'" do
        assert_default(keyboard_shortcuts_preference: "all")
      end

      test "must be one of the configured values" do
        refute_valid({ keyboard_shortcuts_preference: "foo" }, "is invalid: Keyboard shortcuts preference is not included in the list")
      end
    end

    context "animated_images" do
      test "defaults to 'system' (autoplay depends on system/browser defaults)" do
        assert_default(animated_images: "system")
      end

      test "must be one of the configured values (enabled, disabled or system)" do
        assert_valid(animated_images: "disabled")
        assert_valid(animated_images: "enabled")
        assert_valid(animated_images: "system")
        refute_valid({ animated_images: "foo" }, "is invalid: Animated images is not included in the list")
      end
    end

    context "discussions_collapsed_view" do
      test "defaults to false" do
        assert_default(discussions_collapsed_view: false)
      end

      test "allows setting to true or false" do
        record = build(discussions_collapsed_view: true)
        assert record.settings.discussions_collapsed_view

        record = build(discussions_collapsed_view: false)
        refute record.settings.discussions_collapsed_view
      end
    end

    context "link_underlines" do
      test "defaults to true" do
        assert_default(link_underlines: true)
      end

      test "allows setting to true or false" do
        record = build(link_underlines: true)
        assert record.settings.link_underlines

        record = build(link_underlines: false)
        refute record.settings.link_underlines
      end
    end

    context "hovercards" do
      test "defaults to true" do
        assert_default(hovercards_enabled: true)
      end

      test "allows setting to true or false" do
        record = build(hovercards_enabled: true)
        assert record.settings.hovercards_enabled

        record = build(hovercards_enabled: false)
        refute record.settings.hovercards_enabled
      end
    end
  end
end
