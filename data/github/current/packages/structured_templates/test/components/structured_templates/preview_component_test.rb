# typed: true
# frozen_string_literal: true

require "test_helper"

class StructuredTemplates::PreviewComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "renders the template component with disabled elements" do
    input = <<~YAML
    name: Reporting an issue
    description: Report a bug that you've experienced
    body:
      - type: textarea
        attributes:
          label: Please describe the issue
    YAML
    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    repository = create(:repository)
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: repository,
      filename: "structured_bug_report.yml",
    )

    expected_queries = 1
    render_inline StructuredTemplates::PreviewComponent.new(template: template), allowed_queries: expected_queries

    assert_test_selector("issue-form-textarea-element'][disabled='disabled")
  end

  test "renders the issue template component with projects field" do
    input = <<~YAML
    name: Reporting an issue
    description: Report a bug that you've experienced
    body:
      - type: textarea
        attributes:
          label: Please describe the issue
    YAML
    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    repository = create(:repository)
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: repository,
      filename: "structured_bug_report.yml",
    )

    expected_queries = 1
    render_inline StructuredTemplates::PreviewComponent.new(template: template), allowed_queries: expected_queries

    assert_selector("th", text: "Projects")
  end

  test "renders the issue template component with type field if FF is enabled" do
    input = <<~YAML
    name: Reporting an issue
    description: Report a bug that you've experienced
    body:
      - type: textarea
        attributes:
          label: Please describe the issue
    YAML
    config = IssueForms::TemplateConfig.new(input: input, path: "", type_field_enabled: true).load
    repository = create(:repository)
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: repository,
      filename: "structured_bug_report.yml",
    )

    expected_queries = 1
    render_inline StructuredTemplates::PreviewComponent.new(template: template, type_field_enabled: true), allowed_queries: expected_queries

    assert_selector("th", text: "Type")
  end

  test "does not render the issue template component with type field if FF is disabled" do
    input = <<~YAML
    name: Reporting an issue
    description: Report a bug that you've experienced
    body:
      - type: textarea
        attributes:
          label: Please describe the issue
    YAML
    config = IssueForms::TemplateConfig.new(input: input, path: "").load
    repository = create(:repository)
    template = IssueTemplate.new_from_structured_template_config(
      config: config,
      repository: repository,
      filename: "structured_bug_report.yml",
    )

    expected_queries = 1
    render_inline StructuredTemplates::PreviewComponent.new(template: template), allowed_queries: expected_queries

    refute_selector("th", text: "Type")
  end
end
