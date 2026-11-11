# typed: true
# frozen_string_literal: true

module SlashCommands
  class IssueTemplatesCommand < ApplicationSlashCommand
    # This limit was chosen arbitrarily as we need some upper bound. We can revisit in the future if we think this is too low.
    TEMPLATES_LIMIT = 10

    category :markdown

    trigger_on name: "templates", title: "Templates", description: "Insert one of your issue templates"
    allowed_surfaces SlashCommands::ISSUE_BODY_SURFACE

    feature_flag :slash_commands_templates_command

    menu :templates_menu
    fill :insert_template

    def templates_menu
      templates = context.current_repository.preferred_issue_templates
      usable_templates = templates.valid_templates.select(&:is_md_file?).first(TEMPLATES_LIMIT)

      if usable_templates.any?
        items = usable_templates.map do |template|
          template.filename.force_encoding("UTF-8").scrub!
          Item.new(
            id: template.filename,
            text: template.name,
            description: template.about,
            value: template.filename
          )
        end

        menu(:template, items: items)
      else
        blankslate "No issue templates", description: ActiveSupport::SafeBuffer.new("Learn more about <a href=\"#{GitHub.help_url}/articles/about-issue-and-pull-request-templates\" target=\"_blank\">issue templates</a>.")
      end
    end

    def insert_template
      return "" if !data[:template]

      template = context.current_repository.preferred_issue_templates.valid_templates.find do |template|
        template.filename.force_encoding("UTF-8").scrub!
        template.is_md_file? && template.filename == data[:template]
      end

      return "" if !template

      template.body
    end
  end
end
