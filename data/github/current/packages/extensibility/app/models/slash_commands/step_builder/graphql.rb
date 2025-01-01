# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::Graphql < SlashCommands::StepBuilder::PlatformBase
  def query
    step_config["body"]
  end

  def variables_for(command)
    template_data = command.template_data
    variables = step_config["variables"] || {}

    variables.to_h do |key, value|
      if value.is_a?(String)
        [key, render(value, data: template_data)]
      else
        [key, value]
      end
    end
  end
end
