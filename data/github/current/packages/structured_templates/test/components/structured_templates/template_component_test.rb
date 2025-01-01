# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplates::TemplateComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, has_discussions: true)
    @private_repo = create(:private_repository)
    @private_issue = create(:issue, repository: @private_repo)
    @issue = create(:issue, repository: @repo)
    @discussion = create(:discussion, repository: @repo)
  end

  test "does not render without a template" do
    render_inline(
      StructuredTemplates::TemplateComponent.new(template: nil, templatable: @issue)
    )

    refute_component_rendered
  end

  test "does not render with invalid template" do
    input = <<~YAML
    name: invalid example
    description: we are invalid
    body:
      - type: textarea
        attributes:
          placeholder: hello
    YAML

    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: "invalid_template.yml",
    )
    refute_predicate template, :valid?

    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @issue)
    )

    refute_component_rendered
  end

  test "renders basic template" do
    as @user
    @issue.structured_template_inputs = { "#{Digest::SHA256.hexdigest("What is your name?")}": "mona" }

    input = <<~YAML
    name: Hatsune Miku
    description: Everyone's favorite vocaloid
    body:
      - type: markdown
        attributes:
          value: Welcome to the ultimate Miku fan issue template!
      - type: textarea
        attributes:
          label: What is your favorite Miku song, and why?
          description: Be specific!
          placeholder: Please enter a song...
      - type: textarea
        attributes:
          label: What are your favorite pizza toppings?
      - type: input
        attributes:
          label: What is your name?
    YAML

    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: "miku_template.yml",
    )
    assert_predicate template, :valid?

    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @issue), allowed_queries: 4
    )

    assert_test_selector("issue-form-markdown", count: 1)
    assert_test_selector("issue-form-textarea", count: 2)
    assert_test_selector("issue-form-input", count: 1)
    assert_selector("input[name='issue_form[#{Digest::SHA256.hexdigest("What is your name?")}]'][value='mona']")
  end

  test "renders basic template for discussion" do
    input = <<~YAML
    body:
      - type: markdown
        attributes:
          value: Welcome to the ultimate Miku fan issue template!
      - type: textarea
        attributes:
          label: What is your favorite Miku song, and why?
          description: Be specific!
          placeholder: Please enter a song...
      - type: textarea
        attributes:
          label: What are your favorite pizza toppings?
      - type: input
        attributes:
          label: What is your name?
    YAML

    config = DiscussionForms::TemplateConfig.new(input: input, path: "").load
    template = DiscussionTemplate.from_structured_config(
      config: config,
      repository: @repo,
      filename: "general.yml",
    )
    assert_predicate template, :valid?

    @discussion.structured_template_inputs = { "#{Digest::SHA256.hexdigest("What is your name?")}": "mona" }

    as @user
    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @discussion), allowed_queries: 4
    )

    assert_test_selector("issue-form-markdown", count: 1)
    assert_test_selector("issue-form-textarea", count: 2)
    assert_test_selector("issue-form-input", count: 1)
    assert_selector("input[name='discussion_form[#{Digest::SHA256.hexdigest("What is your name?")}]'][value='mona']")
  end

  test "renders with slash commands if enabled" do
    enable_feature_flag(:slash_commands)

    input = <<~YAML
    body:
      - type: markdown
        attributes:
          value: Welcome to the ultimate Miku fan issue template!
      - type: textarea
        attributes:
          label: What is your favorite Miku song, and why?
          description: Be specific!
          placeholder: Please enter a song...
      - type: textarea
        attributes:
          label: What are your favorite pizza toppings?
      - type: input
        attributes:
          label: What is your name?
    YAML

    config = DiscussionForms::TemplateConfig.new(input: input, path: "").load
    template = DiscussionTemplate.from_structured_config(
      config: config,
      repository: @repo,
      filename: "general.yml",
    )
    assert_predicate template, :valid?

    @discussion.structured_template_inputs = { "#{Digest::SHA256.hexdigest("What is your name?")}": "mona" }

    as @user
    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @discussion, preview: false), allowed_queries: 3
    )

    assert_test_selector("issue-form-markdown", count: 1)
    assert_test_selector("issue-form-textarea", count: 2)
    assert_test_selector("issue-form-input", count: 1)
    assert_selector("slash-command-expander", count: 1, visible: false)
    assert_selector("input[name='discussion_form[#{Digest::SHA256.hexdigest("What is your name?")}]'][value='mona']")
  end

  test "does not render invalid discussion template" do
    input = <<~YAML
    body:
      - type: textarea
        attributes:
          placeholder: hello
    YAML

    config = DiscussionForms::TemplateConfig.new(input: input, path: "").load
    template = DiscussionTemplate.from_structured_config(
      config: config,
      repository: @repo,
      filename: "general.yml",
    )
    refute_predicate template, :valid?

    as @user
    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @discussion), allowed_queries: 1
    )
    refute_component_rendered
  end

  test "renders codeblock components when textarea has 'render' key" do
    as @user

    input = <<~YAML
    name: template
    description: we love templates
    body:
      - type: textarea
        attributes:
          label: beep boop
      - type: textarea
        attributes:
          label: badoop
          render: pizza
    YAML

    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: "pizza.yml",
    )
    assert_predicate template, :valid?

    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @issue), allowed_queries: 4
    )

    assert_test_selector("issue-form-textarea", count: 1)
    assert_test_selector("issue-form-codeblock", count: 1)
  end

  test "prefills form fields for inputs and textareas only" do
    as @user
    @issue.structured_template_inputs = {
      "#{Digest::SHA256.hexdigest("Worst pizza topping?")}": "sardines",
      "#{Digest::SHA256.hexdigest("Deep Dish or Thin Crust?")}": "Deep Dish",
      "#{Digest::SHA256.hexdigest("Favorite pizza toppings?")}": "garlic"
    }

    input = <<~YAML
    name: Pizza Form
    description: Tell me about your favorite pizza
    body:
      - type: textarea
        attributes:
          label: Favorite pizza toppings?
      - type: input
        attributes:
          label: Worst pizza topping?
      - type: dropdown
        attributes:
          label: Deep Dish or Thin Crust?
          options:
            - Deep Dish
            - Thin Crust
    YAML

    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @repo,
      filename: "pizza_template.yml",
    )
    assert_predicate template, :valid?

    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @issue), allowed_queries: 4
    )

    assert_selector("input[name='issue_form[#{Digest::SHA256.hexdigest("Worst pizza topping?")}]'][value='sardines']")
    assert_selector("textarea") do |input|
      assert_equal "issue_form_#{Digest::SHA256.hexdigest("Favorite pizza toppings?")}", input[:id]
      assert_equal "garlic", input[:value]
    end
    refute_selector("input[name='issue_form[#{Digest::SHA256.hexdigest("Deep Dish or Thin Crust?")}]'][value='Deep Dish'][checked]", visible: false)
  end

  test "Does render inputs as required for private repositories" do
    as @private_repo.owner
    @private_issue.structured_template_inputs = { what_is_your_name: "mona" }

    input = <<~YAML
    name: Hatsune Miku
    description: Everyone's favorite vocaloid
    body:
      - type: markdown
        attributes:
          value: Welcome to the ultimate Miku fan issue template!
      - type: input
        id: favorite_song
        attributes:
          label: What is your favorite Miku song, and why?
          description: Be specific!
          placeholder: Please enter a song...
        validations:
          required: true
      - type: textarea
        attributes:
          label: What are your favorite pizza toppings?
      - type: input
        attributes:
          label: What is your name?
    YAML

    config = IssueForms::TemplateConfig.new(input: input, path: "")
    config.required_fields_enabled = true
    config = config.load
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: @private_repo,
      filename: "miku_template.yml",
    )
    assert_predicate template, :valid?

    render_inline(
      StructuredTemplates::TemplateComponent.new(template: template, templatable: @private_issue), allowed_queries: 4
    )

    assert_selector("input[name='issue_form[favorite_song]'][required='required']")
  end
end
