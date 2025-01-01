# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class StructuredTemplates::Elements::CodeblockComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "does not render without an element" do
    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: nil, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "does not render with invalid input" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "description" => "Your name",
        "render" => "ruby",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)
    refute_predicate input, :valid?

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    refute_component_rendered
  end

  test "renders for simple codeblock, with references computed from label" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "Hatsune Miku?",
        "render" => "ruby",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("Hatsune Miku?")}']", text: "Hatsune Miku?")
    refute_test_selector("issue-form-codeblock-description")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("Hatsune Miku?")}]", input[:name]
      assert_equal "", input[:value]
      assert_nil input[:required]
      assert_nil input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders with references to user-defined ID if supplied" do
    input_hash = {
      "type" => "textarea",
      "id" => "honk",
      "attributes" => {
        "label" => "Favorite goose?",
        "render" => "ruby",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_honk']", text: "Favorite goose?")
    refute_test_selector("issue-form-codeblock-description")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[honk]", input[:name]
      assert_equal "", input[:value]
      assert_nil input[:required]
      assert_nil input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for codeblock with description with markdown support" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "Hatsune Miku?",
        "description" => "Blue hair, blue tie, hiding in your [wi-fi](https://en.wikipedia.org/wiki/Wi-Fi)",
        "render" => "ruby",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("Hatsune Miku?")}']", text: "Hatsune Miku?")
    assert_test_selector("issue-form-codeblock-description", text: "Blue hair, blue tie, hiding in your wi-fi")
    assert_test_selector("issue-form-codeblock-description'] a[href='https://en.wikipedia.org/wiki/Wi-Fi", text: "wi-fi")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("Hatsune Miku?")}]", input[:name]
      assert_equal "", input[:value]
      assert_equal "description-#{Digest::SHA256.hexdigest("Hatsune Miku?")}", input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for codeblock with prefilled value" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "Hatsune Miku?",
        "description" => "Blue hair, blue tie, hiding in your wi-fi",
        "value" => "I'm thinking Miku, Miku (oo-ee-oo)",
        "render" => "ruby",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("Hatsune Miku?")}']", text: "Hatsune Miku?")
    assert_test_selector("issue-form-codeblock-description", text: "Blue hair, blue tie, hiding in your wi-fi")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("Hatsune Miku?")}]", input[:name]
      assert_equal "I'm thinking Miku, Miku (oo-ee-oo)", input[:value]
      assert_equal "description-#{Digest::SHA256.hexdigest("Hatsune Miku?")}", input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "renders for codeblock with placeholder" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "Hatsune Miku?",
        "render" => "ruby",
        "placeholder" => "Please enter your favorite Miku song...",
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("Hatsune Miku?")}']", text: "Hatsune Miku?")
    refute_test_selector("issue-form-codeblock-description")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("Hatsune Miku?")}]", input[:name]
      assert_equal "", input[:value]
      assert_equal "Please enter your favorite Miku song...", input[:placeholder]
    end
  end

  test "renders for required codeblock" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "Hatsune Miku?",
        "render" => "ruby"
      },
      "validations" => {
        "required" => true,
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("label[for='issue_form_#{Digest::SHA256.hexdigest("Hatsune Miku?")}'][required='required']", text: "Hatsune Miku?")
    refute_test_selector("issue-form-codeblock-description")
    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("Hatsune Miku?")}]", input[:name]
      assert_equal "", input[:value]
      assert_equal "required", input[:required]
      assert_nil input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end

  test "always has monospace font" do
    input_hash = {
      "type" => "textarea",
      "attributes" => {
        "label" => "My code",
        "render" => "ruby"
      },
      "validations" => {
        "required" => true,
      }
    }

    input = StructuredTemplates::Textarea.new(input: input_hash)

    render_inline(
      StructuredTemplates::Elements::CodeblockComponent.new(element: input, base_form_param: :issue_form)
    )

    assert_selector("textarea") do |input|
      assert_equal "issue_form[#{Digest::SHA256.hexdigest("My code")}]", input[:name]
      assert_equal "", input[:value]
      assert_equal "required", input[:required]
      assert_equal "form-control text-mono js-session-resumable", input[:class]
      assert_nil input[:"aria-describedby"]
      assert_nil input[:placeholder]
    end
  end
end
# rubocop:enable ViewComponent/EncouragePreviewsForScannableComponents
