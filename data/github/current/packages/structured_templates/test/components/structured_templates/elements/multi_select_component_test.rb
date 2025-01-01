# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::MultiSelectComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline StructuredTemplates::Elements::MultiSelectComponent.new(element: nil, base_form_param: :issue_form)

    refute_component_rendered
  end

  test "does not render with invalid input" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "description" => "Your name",
        "multiple" => true,
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::MultiSelectComponent.new(element: input, base_form_param: :issue_form)

    refute_predicate input, :valid?
    refute_component_rendered
  end

  test "renders for input with markdown description" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "multiple" => true,
        "description" => "[Choose wisely!](https://twitter.com/loonatheworld)",
        "options" => ["Pete", "Not Pete"],
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::MultiSelectComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']",
      text: "Favorite LOONA member?",
    )
    assert_selector(
      "[data-test-selector='issue-form-multi-select-description'] a[href='https://twitter.com/loonatheworld']",
      text: "Choose wisely!",
    )
  end

  test "renders an extra blank option when not required" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "multiple" => true,
        "options" => ["Pete", "Not Pete"],
      },
      "validations" => {
        "required" => false,
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::MultiSelectComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603']",
      text: "Favorite LOONA member?",
    )
    refute_test_selector("issue-form-multi-select-description")
    assert_selector(
      "input[name='issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603][]'][value='Pete']",
      visible: false,
    )
    assert_selector(
      "input[name='issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603][]'][value='Not Pete']",
      visible: false,
    )
  end

  test "renders required input" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "multiple" => true,
        "options" => ["Pete", "Not Pete"],
      },
      "validations" => {
        "required" => true,
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::MultiSelectComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603'][required='required']",
      text: "Favorite LOONA member?",
    )
    refute_test_selector("issue-form-multi-select-description")
    assert_selector(
      "input[name='issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603][]'][value='Pete']",
      visible: false,
    )
    assert_selector(
      "input[name='issue_form[9a8eac68a997f0d6509d21d58c36b0404ad80c93ff70a97a08bf8ee563ff3603][]'][value='Not Pete']",
      visible: false,
    )
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
