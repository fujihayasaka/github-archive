# typed: true
# frozen_string_literal: true

module SlashCommands
  class StepBuilder::Menu
    def self.build(step_config)
      Page.new(type: :menu, breadcrumb: step_config["label"]) do |command|
        command.menu(
          step_config["id"],
          items: step_config["options"]
        )
      end
    end
  end
end
