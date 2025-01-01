# typed: false
# frozen_string_literal: true

# Inherit from this class to create a step based on a GraphQL query or mutation.
# An example of this is SlashCommands::StepBuilder::AddComment, which makes it
# easy to add a comment to the command subject.
class SlashCommands::StepBuilder::PlatformBase
  def self.build(step_config)
    new(step_config).page
  end

  def query
    raise NotImplementedError(<<~MESSAGE)
      PlatformBase subclasses must implement `#{__method__}`.
      It should return a GraphQL query or mutation.
    MESSAGE
  end

  def variables_for(*)
    raise NotImplementedError(<<~MESSAGE)
      PlatformBase subclasses must implement `#{__method__}`.
      It should return a hash of variables to be passed into query/mutation.
    MESSAGE
  end

  attr_reader :id, :step_config
  def initialize(step_config)
    @step_config = step_config
    @id = step_config["id"]
  end

  def page
    SlashCommands::Page.new(type: :action) do |command|
      execute_query(command)
    end
  end

  def render(template, data:)
    Liquid::Template.parse(
      template,
      error_mode: :strict
    ).render(data)
  end

  # Allow subclasses to transform result. Only called when no errors occur
  def transform_result(result)
    result
  end

  def execute_query(command)
    data_key = id || command.page_number
    context = { viewer: command.current_user }
    variables = variables_for(command)

    result = Platform.execute(
      query,
      target: :public,
      variables: variables,
      context: context,
      raise_exceptions: true
    )

    result_data = result.to_h
    if result_data.key?("errors")
      message = "Problem while executing step #{command.page_number}#{id ? " (#{id})" : ""}: #{result_data}"
      command.flash.error = message
    else
      command.data[data_key] = transform_result(result_data)
    end
  end
end
