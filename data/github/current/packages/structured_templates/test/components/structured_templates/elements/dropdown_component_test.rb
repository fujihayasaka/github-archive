# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::DropdownComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: nil, base_form_param: :issue_form)

    refute_component_rendered
  end

  test "does not render with invalid input" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "description" => "Your name",
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    refute_predicate input, :valid?
    refute_component_rendered
  end

  test "renders for input with markdown description" do
    input_hash = {
      "type" => "input",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "description" => "[Choose wisely!](https://twitter.com/loonatheworld)",
        "options" => ["Pete", "Not Pete"],
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_#{Digest::SHA256.hexdigest("Favorite LOONA member?")}']",
      text: "Favorite LOONA member?",
    )
    assert_selector(
      "[data-test-selector='issue-form-dropdown-description'] a[href='https://twitter.com/loonatheworld']",
      text: "Choose wisely!",
    )
  end

  test "renders an extra blank option when not required" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "options" => ["Pete", "Not Pete"],
      },
      "validations" => {
        "required" => false,
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_#{Digest::SHA256.hexdigest("Favorite LOONA member?")}']",
      text: "Favorite LOONA member?",
    )
    refute_test_selector("issue-form-dropdown-description")
    assert_selector(
      "select[name='issue_form[#{Digest::SHA256.hexdigest("Favorite LOONA member?")}]']", text: "None"
    )
    assert_selector("option[value='None']", visible: false)
    assert_selector("option[value='Pete']", visible: false)
    assert_selector("option[value='Not Pete']", visible: false)
  end

  test "renders required input" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "options" => ["Pete", "Not Pete"],
      },
      "validations" => {
        "required" => true,
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_#{Digest::SHA256.hexdigest("Favorite LOONA member?")}']",
      text: "Favorite LOONA member?",
    )
    refute_test_selector("issue-form-dropdown-description")
    assert_selector(
      "select[name='issue_form[#{Digest::SHA256.hexdigest("Favorite LOONA member?")}]'][required='required']", text: "Pete"
    )
    refute_selector("option[value='None']", visible: false)
    assert_selector("option[value='Pete']", visible: false)
    assert_selector("option[value='Not Pete']", visible: false)
  end

  test "renders with default option if default option is supplied" do
    input_hash = {
      "type" => "dropdown",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "options" => ["Pete", "Not Pete"],
        "default" => 1
      }
    }
    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_#{Digest::SHA256.hexdigest("Favorite LOONA member?")}']",
      text: "Favorite LOONA member?",
    )
    refute_test_selector("issue-form-dropdown-description")
    assert_selector(
      "select[name='issue_form[#{Digest::SHA256.hexdigest("Favorite LOONA member?")}]']", text: "Not Pete"
    )
    refute_selector("option[value='None']", visible: false)
    assert_selector("option[value='Pete']", visible: false)
    assert_selector("option[value='Not Pete']", visible: false)
  end

  test "renders with reference to ID when supplied" do
    input_hash = {
      "type" => "input",
      "id" => "fav",
      "attributes" => {
        "label" => "Favorite LOONA member?",
        "description" => "[Choose wisely!](https://twitter.com/loonatheworld)",
        "options" => ["Pete", "Not Pete"],
      }
    }

    input = StructuredTemplates::Dropdown.new(input: input_hash)

    render_inline StructuredTemplates::Elements::DropdownComponent.new(element: input, base_form_param: :issue_form)

    assert_selector(
      "label[for='issue_form_fav']",
      text: "Favorite LOONA member?",
      )
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
