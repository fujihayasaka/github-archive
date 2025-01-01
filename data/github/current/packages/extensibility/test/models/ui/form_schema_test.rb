# typed: true
# frozen_string_literal: true

require "test_helper"

class UI::FormSchemaTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  def render_form(yaml, validate: true)
    form_data = YAML.load(yaml)
    form_schema = UI::FormSchema.new(form_data, "base_name")

    if validate
      assert_predicate(form_schema, :valid?)
    end

    form_component = SlashCommands::StackComponent.new(form_schema.call)

    render_inline(form_component)
  end

  def render_form_element(yaml, validate: true)
    wrapped_element = [YAML.load(yaml)]
    render_form(wrapped_element.to_yaml, validate: validate)
  end

  test "it renders deprecation warnings with content" do
    # Stub deprecation warnings
    UI::Validator.any_instance.stubs(:deprecation_warnings).returns(stub(full_messages: ["field is deprecated"], any?: true))
    render_form_element(<<~YAML, validate: false)
      type: markdown
      attributes:
        value: |
          # Hello World
    YAML

    assert_selector("[data-test-selector='deprecation-warnings']")
    assert_selector("h1", text: "Hello World")
  end

  test "it can handle invalid components" do
    # Supposed to be an array of hashes
    render_form("--- {}", validate: false)

    assert_selector("[data-test-selector='errors']")
  end

  test "it returns an error component early if the schema is invalid" do
    schema = <<~YAML
      - type: foo
        attributes:
          label: my_input
          format: date
    YAML
    render_form(schema, validate: false)

    assert_selector("[data-test-selector='errors']")
  end

  test "it can handle basic input" do
    render_form_element <<~YAML
      type: input
      attributes:
        label: my_input
    YAML

    assert_selector("input[type='text']") do |input|
      assert_equal "base_name[my_input]", input["name"]
      assert_equal "my_input", input["placeholder"]
      assert_nil input["value"]
      assert_nil input["required"]
    end
  end

  test "it can handle non text input format" do
    render_form_element <<~YAML
      type: input
      attributes:
        label: my_input
        format: date
    YAML

    assert_selector("input[type='date']") do |input|
      assert_equal "base_name[my_input]", input["name"]
      assert_equal "my_input", input["placeholder"]
      assert_nil input["value"]
      assert_nil input["required"]
    end
  end

  test "it can handle non text input type" do
    render_form_element <<~YAML
      type: input
      attributes:
        label: my_input
        format: date
    YAML

    assert_selector("input[type='date']") do |input|
      assert_equal "base_name[my_input]", input["name"]
      assert_equal "my_input", input["placeholder"]
      assert_nil input["value"]
      assert_nil input["required"]
    end
  end

  test "it can handle all input options" do
    render_form_element <<~YAML
      type: input
      attributes:
        label: Operating System
        id: os
        description: What operating system are you using?
        placeholder: ex. OSX Mountain Lion
        value: "operating system"
        format: text
      validations:
        required: true
    YAML

    assert_selector("label", text: "Operating System")
    assert_selector("input[type='text']") do |input|
      assert_equal "base_name[os]", input["name"]
      assert_equal "ex. OSX Mountain Lion", input["placeholder"]
      assert_equal "operating system", input["value"]
      assert_equal "required", input["required"]

      assert_selector("##{input['aria-describedby']}", text: "What operating system are you using?")
    end
  end

  test "it can handle single dropdowns" do
    render_form_element <<~YAML
      type: dropdown
      attributes:
        label: Version
        description: What version of our software are you running?
        multiple: false
        value: 1.0.3 (Edge)
        options:
        - label: 1.0.2 (Default)
        - label: 1.0.3 (Edge)
      validations:
        required: true
    YAML

    assert_selector("label", text: "Version")
    assert_selector("select") do |select|
      refute_predicate select, :multiple?
      assert_equal "base_name[Version]", select["name"]
      assert_equal "required", select["required"]
      assert_selector("##{select['aria-describedby']}", text: "What version of our software are you running?")

    end

    assert_selector("option", count: 3) # Includes a blank option too
    assert_selector("option[value='1.0.2 (Default)']")
    assert_selector("option[value='1.0.3 (Edge)']")
    assert_selector("option[selected]") do |first_option_tag|
      assert_equal "1.0.3 (Edge)", first_option_tag.text
      assert_equal "1.0.3 (Edge)", first_option_tag.value
    end
  end

  test "it can handle multi dropdowns" do
    render_form_element <<~YAML
      type: dropdown
      attributes:
        label: Version
        description: What version of our software are you running?
        multiple: true
        value: ["1.0.3 (Edge)"]
        options:
        - label: 1.0.2 (Default)
        - label: 1.0.3 (Edge)
      validations:
        required: true
    YAML

    assert_selector("label", text: "Version")
    assert_selector("select") do |select|
      assert_predicate select, :multiple?
      assert_equal "base_name[Version][]", select["name"]
      assert_equal "required", select["required"]

      assert_selector("##{select['aria-describedby']}", text: "What version of our software are you running?")
    end
    assert_selector("option[selected]") do |first_option_tag|
      assert_equal "1.0.3 (Edge)", first_option_tag.text
      assert_equal "1.0.3 (Edge)", first_option_tag.value
    end
  end

  test "dropdown with id property" do
    render_form_element <<~YAML
      type: dropdown
      attributes:
        label: What is the priority?
        id: priority
        options:
        - label: Important
        - label: Not important
      validations:
        required: true
    YAML

    assert_selector("label", text: "What is the priority?")
    assert_selector("select") do |select|
      assert_equal "base_name[priority]", select["name"]
    end
  end

  test "it defaults to checkboxes" do
    render_form_element <<~YAML
      type: checkboxes
      attributes:
        label: Code of Conduct
        description: The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members
        options:
        - label: I agree to follow this project's [Code of Conduct](link/to/coc)
          value: coc_agreed
          required: true
    YAML

    assert_selector("label", text: "Code of Conduct")
    assert_selector("label", text: "I agree to follow this project's [Code of Conduct](link/to/coc)")
    assert_selector('input[type="checkbox"]') do |input|
      assert_equal "base_name[Code of Conduct]", input["name"]
      assert_equal "coc_agreed", input["value"]
    end
  end

  test "it can handle checkboxes input type" do
    render_form_element <<~YAML
      type: checkboxes
      attributes:
        label: Code of Conduct
        description: The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members
        value: coc_agreed
        options:
        - label: I agree to follow this project's [Code of Conduct](link/to/coc)
          value: coc_agreed
          required: true
    YAML

    assert_selector("label", text: "Code of Conduct")
    assert_selector("label", text: "I agree to follow this project's [Code of Conduct](link/to/coc)")
    assert_selector('input[type="checkbox"]') do |input|
      assert_equal "base_name[Code of Conduct]", input["name"]
      assert_equal "coc_agreed", input["value"]
    end

    assert_selector(".form-group-body") do |body|
      assert_selector("##{body['aria-describedby']}", text: "The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members")
    end
  end

  test "checkboxes with id property" do
    render_form_element <<~YAML
      type: checkboxes
      attributes:
        label: What is the priority?
        id: priority
        options:
        - label: Important
      validations:
        required: true
    YAML

    assert_selector("label", text: "What is the priority?")
    assert_selector('input[type="checkbox"]') do |input|
      assert_equal "base_name[priority]", input["name"]
    end
  end

  test "it can handle radio buttons" do
    render_form_element <<~YAML
      type: checkboxes
      attributes:
        label: Code of Conduct
        description: The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members
        value: coc_agreed
        options:
        - label: I agree to follow this project's [Code of Conduct](link/to/coc)
          value: coc_agreed
          required: true
    YAML

    assert_selector("label", text: "Code of Conduct")
    assert_selector("label", text: "I agree to follow this project's [Code of Conduct](link/to/coc)")
    assert_selector('input[type="checkbox"]') do |input|
      assert_equal "base_name[Code of Conduct]", input["name"]
      assert_equal "coc_agreed", input["value"]
    end

    assert_selector(".form-group-body") do |body|
      assert_selector("##{body['aria-describedby']}", text: "The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members")
    end

    assert_selector("input[checked]") do |first_option_tag|
      assert_equal "coc_agreed", first_option_tag.value
    end
  end

  test "it can handle markdown" do
    render_form_element <<~YAML
      type: markdown
      attributes:
        value: |
          # Hello World
    YAML

    assert_selector("h1", text: "Hello World")
  end

  test "it can handle textarea" do
    render_form_element <<~YAML
      type: textarea
      attributes:
        label: Operating System
        id: os
        description: What operating system are you using?
        placeholder: ex. OSX Mountain Lion
        value: "operating system"
      validations:
        required: true
    YAML

    assert_selector("label", text: "Operating System")
    assert_selector("textarea") do |textarea|
      assert_equal "base_name[os]", textarea["name"]
      assert_equal "operating system", textarea["value"]
      refute_nil textarea["required"]
      ids = textarea["aria-describedby"].split(" ")
      first_id = ids.first
      second_id = ids.second
      assert_selector("##{first_id}", text: "What operating system are you using?")
      assert_selector("##{second_id}", text: "ex. OSX Mountain Lion")
    end
  end

  test "it can handle checkboxes" do
    render_form_element <<~YAML
      type: checkboxes
      attributes:
        label: Code of Conduct
        id: coc
        description: The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members
        value: coc_agreed
        options:
        - label: I agree to follow this project's [Code of Conduct](link/to/coc)
          value: coc_agreed
          required: true
    YAML

    assert_selector("label", text: "Code of Conduct")
    assert_selector("label", text: "I agree to follow this project's [Code of Conduct](link/to/coc)")
    assert_selector('input[type="checkbox"]') do |input|
      assert_equal "base_name[coc]", input["name"]
      assert_equal "coc_agreed", input["value"]
    end

    assert_selector(".form-group-body") do |body|
      assert_selector("##{body['aria-describedby']}", text: "The Code of Conduct represents a policy that governs how individuals act while interacting with this project and its members")
    end
  end
end
