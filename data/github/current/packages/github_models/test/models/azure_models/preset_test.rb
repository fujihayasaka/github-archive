# typed: true
# frozen_string_literal: true

require "test_helper"

class AzureModelsPresetTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @default_attrs = {
      conversation_history: [].to_json,
      parameters: {}.to_json,
    }

    @default_preset = AzureModels::Preset.create(
      user: @user,
      name: "preset",
      conversation_history: [
        { "prompt" => "hello", "response" => "how are you" },
        { "prompt" => "good", "response" => "bad" },
      ].to_json,
      parameters: {
        "max_tokens" => 100,
        "temperature" => 0.5,
      }.to_json,
    )
  end

  context "validations" do
    test "a user cannot have multiple presets with the same name" do
      AzureModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      # Intentionally also test for case-insensitive
      preset = AzureModels::Preset.new(user: @user, name: "PreSet1", **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name of preset already exists"
    end

    test "a user can have multiple presets with different names" do
      AzureModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      preset = AzureModels::Preset.new(user: @user, name: "preset2", **@default_attrs)

      assert_predicate preset, :valid?
    end

    test "preset's name must not exceed 100 characters" do
      preset = AzureModels::Preset.new(user: @user, name: "a" * 101, **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name is too long (maximum is 100 characters)"
    end

    test "preset's description must not exceed 255 characters" do
      preset = AzureModels::Preset.new(user: @user, name: "preset", description: "a" * 256, **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Description is too long (maximum is 255 characters)"
    end

    test "preset's name must not be the reserved name upon creation" do
      preset = AzureModels::Preset.create(
        user: @user,
        name: AzureModels::Preset::RESERVED_DEFAULT_NAME,
        **@default_attrs
      )

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name cannot be '#{AzureModels::Preset::RESERVED_DEFAULT_NAME}'"
    end

    test "preset's name must not be the reserved name upon update" do
      preset = AzureModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      preset.update(name: AzureModels::Preset::RESERVED_DEFAULT_NAME)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name cannot be '#{AzureModels::Preset::RESERVED_DEFAULT_NAME}'"
    end

    test "preset's conversation history must not exceed MAX_CONVERSATION_HISTORY_SIZE" do
      AzureModels::Preset.stub_const(:MAX_CONVERSATION_HISTORY_SIZE, 1.byte) do
        oversized_history = "a" * (AzureModels::Preset::MAX_CONVERSATION_HISTORY_SIZE + 1)
        preset = AzureModels::Preset.new(user: @user, name: "valid_name", conversation_history: oversized_history, **@default_attrs)

        refute_predicate preset, :valid?
        assert_includes preset.errors.full_messages,
          "Conversation history cannot exceed #{AzureModels::Preset::MAX_CONVERSATION_HISTORY_SIZE / 1.megabyte} MB"
      end
    end
  end

  context "lifecycle" do
    test "url_identifier is set after initialization" do
      preset = AzureModels::Preset.new(user: @user, name: "preset haha", **@default_attrs)

      assert_predicate preset, :valid?
      assert_equal "#{@user.display_login}/preset-haha", preset.url_identifier
    end
  end

  test "#parsed_conversation_history" do
    parsed_history = @default_preset.parsed_conversation_history

    assert_equal 2, parsed_history.length

    assert_equal "hello", parsed_history.first["prompt"]
    assert_equal "how are you", parsed_history.first["response"]

    assert_equal "good", parsed_history.second["prompt"]
    assert_equal "bad", parsed_history.second["response"]
  end

  test "#parsed_parameters" do
    parsed_params = @default_preset.parsed_parameters

    assert_equal 100, parsed_params["max_tokens"]
    assert_equal 0.5, parsed_params["temperature"]
    assert_nil parsed_params["bad_key"]
  end
end
