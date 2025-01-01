# typed: true
# frozen_string_literal: true


require "test_helper"

class SlashCommands::ValidatorTest < GitHub::TestCase
  def test_it_expects_a_hash
    [1, "foo", [], true, nil].each do |val|
      validator = SlashCommands::Validator.new(val)
      refute_predicate validator, :valid?
      assert_equal ["Expected schema to be an hash of elements, but was `#{val.class}`"], validator.errors.full_messages
    end
  end

  def test_it_expects_only_certain_top_level_keys
    validator = SlashCommands::Validator.new({ trigger: "", title: "", surfaces: [], description: "", steps: [], more_steps: [] })
    refute_predicate validator, :valid?
    assert_equal ["`schema` was not expected to include the key `more_steps`"], validator.errors.full_messages
  end

  def test_doesnt_require_surfaces
    validator = SlashCommands::Validator.new({ trigger: "", title: "", description: "", steps: [] })
    assert_predicate validator, :valid?
  end

  def test_it_is_missing_keys
    validator = SlashCommands::Validator.new({ trigger: "", title: "", something_else: "", steps: [] })
    refute_predicate validator, :valid?
    assert_equal [
      "`schema` was expected to include the key `description`",
      "`schema` was not expected to include the key `something_else`"
    ], validator.errors.full_messages
  end

  def test_it_validates_valid_types
    base_schema = { trigger: 1, title: 2, surfaces: ["issue"], description: 3, steps: [] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`trigger` must be a `String`",
      "`title` must be a `String`",
      "`description` must be a `String`"
    ], validator.errors.full_messages
  end

  def test_it_validates_top_level_string_lengths
    base_schema = { trigger: nil, title: nil, surfaces: ["issue"], description: nil, steps: [] }
    errors = []
    SlashCommands::Validator::VALID_STRING_LENGTHS.each do |key, length|
      base_schema[key.to_sym] = "a" * (length + 1)
      errors << "`#{key}` must be at most `#{length}` characters long, but was `#{length + 1}`"
    end

    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal errors, validator.errors.full_messages
  end

  def test_it_validates_surfaces
    base_schema = { trigger: "string", title: "string", surfaces: {}, description: "string", steps: [] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`surfaces` was expected to be an `Array` but was a `Hash`"
    ], validator.errors.full_messages
  end

  def test_it_validates_for_supported_surfaces
    base_schema = { trigger: "string", title: "string", surfaces: [1], description: "string", steps: [] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`surfaces` `1` must be one of `discussion`, `pull_request`, `pull_request_body`, `pull_request_comment`, `issue`, `issue_body`, or `issue_comment`"
    ], validator.errors.full_messages
  end

  def test_it_validates_steps
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: {} }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps` was expected to be an `Array` but was a `Hash`"
    ], validator.errors.full_messages
  end

  def test_it_validates_a_step
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [1] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0]` was expected to be a hash, but was `Integer`"
    ], validator.errors.full_messages
  end

  def test_detects_duplicate_names_in_steps
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "menu", id: "foo", options: [] },
      { type: "menu", id: "bar", options: [] },
      { type: "menu", id: "foo", options: [] }
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0].id` was not unique",
      "`steps[2].id` was not unique"
    ], validator.errors.full_messages
  end

  def test_limits_fields_to_25
    steps = 27.times.map { |_i| { type: "menu", id: SecureRandom.hex, options: [] } }
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: steps }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps` is currently limited to `25`, but you currently have `27`. Please remove at least `2`.",
    ], validator.errors.full_messages
  end

  def test_step_has_invalid_type
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "menus", items: ["foo"] },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0].type` is not a valid type: `menus`",
    ], validator.errors.full_messages
  end

  ## Fill Step

  def test_fill_template_and_template_path
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "fill", template: "foo" },
      { type: "fill", template_path: "foo" },
      { type: "fill", templates: "foo" },
      { type: "fill", template: "foo", template_path: "foo" },
      { type: "fill", template: 1 },
      { type: "fill", template_path: 2 },
      { type: "fill", template: "a" * (SlashCommands::Validator::MAX_TEMPLATE_LENGTH + 1) },
      { type: "fill", template_path: "a" * (SlashCommands::Validator::MAX_TEMPLATE_LENGTH + 1) },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[2]` must have `template` or `template_path` key defined",
      "`steps[3]` cannot define both `template` and `template_path` keys defined",
      "`steps[4].template` must be a `String`",
      "`steps[5].template_path` must be a `String`",
      "`steps[6].template` must be at most `#{SlashCommands::Validator::MAX_TEMPLATE_LENGTH}` characters long, but was `#{SlashCommands::Validator::MAX_TEMPLATE_LENGTH + 1}`",
      "`steps[7].template_path` must be at most `#{SlashCommands::Validator::MAX_TEMPLATE_LENGTH}` characters long, but was `#{SlashCommands::Validator::MAX_TEMPLATE_LENGTH + 1}`"
    ], validator.errors.full_messages
  end

  def test_fill_submit_form
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "fill", template: "foo" },
      { type: "fill", template_path: "foo", submit_form: "foo" },
      { type: "fill", template_path: "foo", submit_form: 1 },
      { type: "fill", template_path: "foo", submit_form: nil },
      { type: "fill", template_path: "foo", submit_form: true },
      { type: "fill", template_path: "foo", submit_form: false },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[1].submit_form` was expected to be a `Boolean` but was `String`",
      "`steps[2].submit_form` was expected to be a `Boolean` but was `Integer`",
      "`steps[3].submit_form` was expected to be a `Boolean` but was `NilClass`",
    ], validator.errors.full_messages
  end

  ## repository_dispatch Step

  def test_repository_dispatch_step
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "repository_dispatch" },
      { type: "repository_dispatch", eventType: "foo" },
      { type: "repository_dispatch", eventType: "foo", repository: "github/github" },
      { type: "repository_dispatch", eventType: "foo", repository: {} },
      { type: "repository_dispatch", eventType: {} },
      { type: "repository_dispatch", eventType: "foo", repository: "github github" },
      ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0]` must have `eventType` key defined",
      "`steps[4]` must have `eventType` key defined",
      "`steps[5].repository` was expected to be in the form `<repository owner login>/<repository name>`"
    ], validator.errors.full_messages
  end

  ## Form Step

  def test_form_step_has_expected_keys
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "form", template: "foo" },
      { type: "form", body: "foo" },
      { type: "form", style: "embedded", body: [] },
      { type: "form", style: "embedded", body: [] },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0]` was expected to include the keys `style` and `body`",
      "`steps[0]` was not expected to include the key `template`",
      "`steps[1]` was expected to include the key `style`"
    ], validator.errors.full_messages
  end

  def test_form_step_has_valid_form_style
    steps = [{ type: "form", style: "banana", body: [] }]
    steps += ::SlashCommands::Page::FORM_STYLES.map(&:to_s).map do |style|
      { type: "form", style: style, body: [] }
    end

    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: steps }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0].style` `banana` must be one of `dialog`, `embedded`, or `modal`",
    ], validator.errors.full_messages
  end

  def test_form_step_has_valid_form
    steps = [
      { type: "form", style: "embedded", body: [] },
      { type: "form", style: "embedded", body: ["a"] },
      { type: "form", style: "embedded", body: [{ type: "input", attributes: { label: "name" } }] },
    ]

    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: steps }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[1].body[0]` was expected to be a `Hash` but was a `String`"
    ], validator.errors.full_messages
  end

  test "form actions" do
    steps = [
      { type: "form", style: "embedded", body: [], actions: 1 },
      { type: "form", style: "embedded", body: [], actions: { submit: 1, cancel: 1 } },
      { type: "form", style: "embedded", body: [], actions: { submit: "create", cancel: "close" } },
    ]

    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: steps }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0].actions` was expected to be a `Hash` but was `Integer`",
      "`steps[1].actions.submit` was expected to be a `String` but was `Integer`",
      "`steps[1].actions.cancel` was expected to be a `String` but was `Integer`",
    ], validator.errors.full_messages
  end

  ## Menu Step

  def test_good_menu_step
    command_config = {
      trigger: "string",
      title: "string",
      surfaces: ["issue"],
      description: "string",
      steps: [
        { type: "menu", id: "environment", label: "Pick an environment", options: ["foo"] },
      ]
    }

    validator = SlashCommands::Validator.new(command_config)
    assert_predicate validator, :valid?
  end

  def test_menu_step_validates_items
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "menu", id: "foobar", options: ["foo"] },
      { type: "menu", id: "banana", options: "foo" },
      { type: "menu", item: "embedded" },
      { type: "menu", id: "foobar2", options: [1] },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[1].options` was expected to be an `Array` but was a `String`",
      "`steps[2]` was expected to include the keys `id` and `options`",
      "`steps[2]` was not expected to include the key `item`",
      "`steps[3].options[0]` must be a `String`"
    ], validator.errors.full_messages
  end

  def test_menu_max_string_length
    base_schema = { trigger: "string", title: "string", surfaces: ["issue"], description: "string", steps: [
      { type: "menu", id: "a" * (SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH + 1), options: ["foo"] },
      { type: "menu", id: "foobar2", options: ["a" * (SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH + 1)] },
    ] }
    validator = SlashCommands::Validator.new(base_schema)
    refute_predicate validator, :valid?
    assert_equal [
      "`steps[0].id` must be at most `#{SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH}` characters long, but was `#{SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH + 1}`",
      "`steps[1].options[0]` must be at most `#{SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH}` characters long, but was `#{SlashCommands::Validator::DEFAULT_MAX_STRING_LENGTH + 1}`"
    ], validator.errors.full_messages
  end
end
