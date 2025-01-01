# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::CheckboxComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: nil, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "does not render with invalid input" do
    input_hash = {
      "type" => "checkboxes",
      "attributes" => {
        "foo" => "bar",
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)
    refute_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "works with an empty element id" do
    input_hash = {
      "type" => "checkboxes",
      "attributes" => {
        "label" => "simple",
        "options" => [
          { "label" => "Example checkbox" }
        ],
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)
    assert_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("simple")}_#{Digest::SHA256.hexdigest("Example checkbox")}']", text: "Example checkbox")
    assert_selector("input[type='checkbox'][id='issue_form_#{Digest::SHA256.hexdigest("simple")}_#{Digest::SHA256.hexdigest("Example checkbox")}']")
  end

  test "works with a mix of required and not required checkboxes" do
    input_hash = {
      "type" => "checkboxes",
      "id" => "field_1",
      "attributes" => {
        "label" => "Test Checkboxes",
        "options" => [
          { "label" => "Example checkbox" },
          {
            "label" => "Another checkbox",
            "required" => true,
          },
        ],
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)
    assert_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_field_1_#{Digest::SHA256.hexdigest("Example checkbox")}']", text: "Example checkbox")
    assert_selector("input[type='checkbox'][id='issue_form_field_1_#{Digest::SHA256.hexdigest("Example checkbox")}']")
    assert_selector("label[for='issue_form_field_1_#{Digest::SHA256.hexdigest("Another checkbox")}'][required='required']", text: "Another checkbox")
    assert_selector("input[type='checkbox'][id='issue_form_field_1_#{Digest::SHA256.hexdigest("Another checkbox")}'][required='required']")
  end

  test "renders codeblocks, bold and italic formatted text in label" do
    input_hash = {
      "type" => "checkboxes",
      "id" => "field_1",
      "attributes" => {
        "label" => "Test Checkboxes",
        "options" => [
          { "label" => "**I read the Code of Conduct**"  },
          { "label" => "_I promise_"  },
          { "label" => "`pinky promise`"  },
        ],
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)
    assert_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_field_1_#{Digest::SHA256.hexdigest("**I read the Code of Conduct**")}']") do
      assert_selector("strong", text: "I read the Code of Conduct")
    end
    assert_selector("input[type='checkbox'][id='issue_form_field_1_#{Digest::SHA256.hexdigest("**I read the Code of Conduct**")}']")

    assert_selector("label[for='issue_form_field_1_#{Digest::SHA256.hexdigest("_I promise_")}']") do
      assert_selector("em", text: "I promise")
    end
    assert_selector("input[type='checkbox'][id='issue_form_field_1_#{Digest::SHA256.hexdigest("_I promise_")}']")

    assert_selector("label[for='issue_form_field_1_#{Digest::SHA256.hexdigest("`pinky promise`")}']") do
      assert_selector("code", text: "pinky promise")
    end
    assert_selector("input[type='checkbox'][id='issue_form_field_1_#{Digest::SHA256.hexdigest("`pinky promise`")}']")
  end

  test "renders hyperlinks" do
    input_hash = {
      "type" => "checkboxes",
      "id" => "field_1",
      "attributes" => {
        "label" => "Test Checkboxes",
        "options" => [
          { "label" => "I read the [code of conduct](https://neopets.com)"  },
        ],
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)
    assert_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_field_1_41b56781b2b48d2c8a1e4fe82c9bce1a1b1fd4ae38895a98e95e84ce716241cd']", text: "I read the") do
      assert_selector("a[href='https://neopets.com']", text: "code of conduct")
    end
    assert_selector("input[type='checkbox'][id='issue_form_field_1_41b56781b2b48d2c8a1e4fe82c9bce1a1b1fd4ae38895a98e95e84ce716241cd']")
  end

  test "renders with references to user-defined ID if supplied" do
    input_hash = {
      "type" => "checkboxes",
      "id" => "honk",
      "attributes" => {
        "label" => "Untitled Goose Checkbox",
        "options" => [
          { "label" => "Example checkbox" },
        ]
      }
    }

    input = StructuredTemplates::Checkboxes.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CheckboxComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_honk']", text: "Untitled Goose Checkbox")
    assert_selector("input[type='checkbox'][id='issue_form_honk_#{Digest::SHA256.hexdigest("Example checkbox")}']")
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
