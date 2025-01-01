# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::MarkdownComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline(
      StructuredTemplates::Elements::MarkdownComponent.new(element: nil, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "does not render with invalid value" do
    input_hash = {
      "type" => "markdown",
      "attributes" => {
        "value" => nil,
      }
    }

    input = StructuredTemplates::Markdown.new(input: input_hash)
    refute_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::MarkdownComponent.new(element: input, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "renders plain text markdown input type" do
    input_hash = {
      "type" => "markdown",
      "attributes" => {
        "value" => "This is a simple description",
      }
    }

    input = StructuredTemplates::Markdown.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::MarkdownComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_test_selector("issue-form-markdown", text: "This is a simple description")
  end

  test "renders markdown" do
    input_hash = {
      "type" => "markdown",
      "attributes" => {
        "value" => "This is a [test](http://example.com)",
      }
    }

    input = StructuredTemplates::Markdown.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::MarkdownComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_test_selector("issue-form-markdown")
    assert_test_selector("issue-form-markdown'] a[href='http://example.com", text: "test")
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
