# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::PresetTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @default_attrs = {
      parameters: {}.to_json,
    }

    @default_preset = GitHubModels::Preset.create(
      user: @user,
      name: "preset",
      parameters: {
        "system_prompt" => "system prompt",
        "chat_prompt" => "chat prompt",
        "max_tokens" => 100,
        "temperature" => 0.5,
      }.to_json,
    )
  end

  context "validations" do
    test "a user cannot have multiple presets with the same name" do
      GitHubModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      # Intentionally also test for case-insensitive
      preset = GitHubModels::Preset.new(user: @user, name: "PreSet1", **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name of preset already exists"
    end

    test "a user can have multiple presets with different names" do
      GitHubModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      preset = GitHubModels::Preset.new(user: @user, name: "preset2", **@default_attrs)

      assert_predicate preset, :valid?
    end

    test "preset's name must not exceed 100 characters" do
      preset = GitHubModels::Preset.new(user: @user, name: "a" * 101, **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name is too long (maximum is 100 characters)"
    end

    test "preset's name must not be the reserved name upon creation" do
      preset = GitHubModels::Preset.create(
        user: @user,
        name: GitHubModels::Preset::RESERVED_DEFAULT_NAME,
        **@default_attrs
      )

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name cannot be '#{GitHubModels::Preset::RESERVED_DEFAULT_NAME}'"
    end

    test "preset's name must not be the reserved name upon update" do
      preset = GitHubModels::Preset.create(user: @user, name: "preset1", **@default_attrs)

      preset.update(name: GitHubModels::Preset::RESERVED_DEFAULT_NAME)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "Name cannot be '#{GitHubModels::Preset::RESERVED_DEFAULT_NAME}'"
    end

    test "a preset cannot be created for an organization" do
      org = create(:organization)
      preset = GitHubModels::Preset.new(user: org, name: "preset1", **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "User must not be of Organization type"
    end

    test "a preset cannot be created for a bot user" do
      bot = make_integration_installation(target: @user).bot
      preset = GitHubModels::Preset.new(user: bot, name: "preset1", **@default_attrs)

      refute_predicate preset, :valid?
      assert_includes preset.errors.full_messages, "User must not be of Bot type"
    end
  end

  context "lifecycle" do
    test "url_identifier is set after initialization" do
      preset = GitHubModels::Preset.new(user: @user, name: "preset haha", **@default_attrs)

      assert_predicate preset, :valid?
      assert_equal "#{@user.display_login}/preset-haha", preset.url_identifier
    end
  end

  test "#parsed_parameters disregards invalid parameters" do
    parsed_params = @default_preset.parsed_parameters
    expected = {
      system_prompt: "system prompt",
      chat_prompt: "chat prompt",
    }

    assert_equal expected, parsed_params
  end
end
