# typed: true
# frozen_string_literal: true

module SlashCommands
  class StepBuilder::Form
    def self.build(step_config)
      new(step_config).page
    end

    attr_reader :step_config
    def initialize(step_config)
      @step_config = step_config
    end

    def page
      form_style = Page::FORM_STYLES.find do |form_style|
        form_style.to_s == step_config["style"]
      end || Page::FORM_STYLES.first

      Page.new(type: :form, form_style: form_style) do |command|
        render(command)
      end
    end

    def render(command)
      GitHub.dogstats.increment("slash_commands.form_rendered", tags: ["style:#{step_config["style"]}"])

      form_schema = UI::FormSchema.new(step_config["body"], "command")

      form_actions = {}
      if actions = step_config["actions"]
        if actions["submit"]
          form_actions[:submit_action] = UI.submit_button(actions["submit"])
        end

        if actions["cancel"]
          form_actions[:close_action] = UI.close_button(actions["cancel"])
        end
      end
      command.form(form_schema.call, pt: 3, **form_actions)
    end
  end
end
