# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class PreviewComponent < ApplicationComponent
    ISSUE_TEMPLATE_ORDERED_FRONTMATTER_ATTRIBUTES_TO_DISPLAY = {
      name: "Name",
      about: "About",
      labels_string: "Labels",
      assignees_string: "Assignees",
      projects_string: "Projects"
    }

    DISCUSSION_TEMPLATE_ORDERED_FRONTMATTER_ATTRIBUTES_TO_DISPLAY = {
      title: "Title",
      labels_string: "Labels",
    }

    def initialize(template:, type_field_enabled: false)
      @template = template
      @type_field_enabled = type_field_enabled
    end

    def call
      safe_join(
        [
          markdown_table_as_html,
          render(TemplateComponent.new(template: template, preview: true)),
        ]
      )
    end

    private

    attr_reader :template, :type_field_enabled

    def markdown_table_as_html
      content_tag(:article, class: "markdown-body pb-3") do
        GitHub::Goomba::MarkdownPipeline.to_html(frontmatter_markdown_table)
      end
    end

    def frontmatter_markdown_table
      frontmatter_attributes_to_display = if template.is_a?(DiscussionTemplate)
        DISCUSSION_TEMPLATE_ORDERED_FRONTMATTER_ATTRIBUTES_TO_DISPLAY
      else
        if type_field_enabled
          ISSUE_TEMPLATE_ORDERED_FRONTMATTER_ATTRIBUTES_TO_DISPLAY.merge({ type: "Type" })
        else
          ISSUE_TEMPLATE_ORDERED_FRONTMATTER_ATTRIBUTES_TO_DISPLAY
        end
      end

      header = "|#{frontmatter_attributes_to_display.values.join("|")}|"
      header_separator = "|#{':--|' * frontmatter_attributes_to_display.keys.length}"

      values = frontmatter_attributes_to_display.keys.map do |attribute|
        template.public_send(attribute)
      end.join("|")

      [header, header_separator, "|#{values}|\n"].join("\n")
    end
  end
end
