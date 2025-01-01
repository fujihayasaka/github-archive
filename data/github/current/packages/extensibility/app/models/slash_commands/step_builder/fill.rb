# typed: true
# frozen_string_literal: true
require "liquid"

module SlashCommands
  class StepBuilder::Fill
    def self.build(step_config)
      new(step_config).page
    end

    attr_reader :step_config
    def initialize(step_config)
      @step_config = step_config
    end

    def page
      Page.new(type: :fill, submit_form: step_config["submit_form"]) do |command|
        render(command)
      end
    end

    def render(command)
      template_string = find_template_string(command.template_source_repository)

      template = Liquid::Template.parse(template_string, error_mode: :strict)
      markdown = template.render(command.template_data)

      ActiveSupport::SafeBuffer.new(markdown)
    end

    def find_template_string(repository)
      if step_config["template_path"].present?
        begin
          repository.tree_entry(
            repository.default_oid,
            step_config["template_path"]
          )&.data
        rescue GitRPC::NoSuchPath
          step_config.fetch("template") { "Template not found" }
        end
      else
        step_config.fetch("template") { "Template not found" }
      end
    end
  end
end
