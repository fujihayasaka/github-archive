# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::InputComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: nil, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "does not render with invalid input" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "description" => "Your name",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)
    refute_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "renders for simple input, using references computed from label" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']", text: "Favorite LOONA member?")
    refute_test_selector("issue-form-input-description")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603]", input[:name]
      assert_nil input[:value]
      assert_nil input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for input with markdown description" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "description" => "[Choose wisely!](https://twitter.com/loonatheworld)",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']", text: "Favorite LOONA member?")
    assert_test_selector("issue-form-input-description'] a[href='https://twitter.com/loonatheworld", text: "Choose wisely!")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603]", input[:name]
      assert_nil input[:value]
      assert_equal "description-9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603", input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for input with prefilled value" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "description" => "Choose wisely!",
        "value" => "HaSeul",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']", text: "Favorite LOONA member?")
    assert_test_selector("issue-form-input-description", text: "Choose wisely!")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603]", input[:name]
      assert_equal "HaSeul", input[:value]
      assert_equal "description-9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603", input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for input with placeholder" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "placeholder" => "Please enter your favorite member...",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']", text: "Favorite LOONA member?")
    refute_test_selector("issue-form-input-description")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603]", input[:name]
      assert_equal "Please enter your favorite member...", input[:placeholder]
      assert_nil input[:required]
      assert_nil input[:value]
    end
  end

  test "renders with references to user-defined ID if supplied" do
    input_hash = {
      "type" => "input",
      "id" => "honk",
      "attributes" => {
        "label" => "Favorite goose?",
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_honk']", text: "Favorite goose?")
    refute_test_selector("issue-form-input-description")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[honk]", input[:name]
      assert_nil input[:required]
      assert_nil input[:value]
    end
  end

  test "renders required input" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "placeholder" => "Please enter your favorite member...",
      },
      "validations" => {
        "required" => true,
      }
    }

    input = StructuredTemplates::Input.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::InputComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603'][required='required']", text: "Favorite LOONA member?")
    refute_test_selector("issue-form-input-description")
    assert_selector("input[type='text']") do |input|
      assert_equal "issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603]", input[:name]
      assert_equal "Please enter your favorite member...", input[:placeholder]
      assert_equal "required", input[:required]
      assert_nil input[:value]
    end
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
