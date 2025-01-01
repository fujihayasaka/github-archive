# typed: true
# frozen_string_literal: true

class GitHubModels::Documentation::CodeSampleComponent < ApplicationComponent

  def initialize(model_name:, publisher_name:, model_capabilities:, task:, language:, sdk:, exceptions:, parameters_as_template:)
    @model_name = model_name
    @model = "#{publisher_name}/#{model_name}"

    # Todo: idea, rename to @render_max_tokens, and put all conditions here. Keep templates cleaner and less to edit in future
    @supports_system_prompt = model_capabilities[:system_prompt]
    @supports_max_tokens = model_capabilities[:max_tokens]
    @supports_temperature = model_capabilities[:temperature]
    @supports_top_p = model_capabilities[:top_p]

    @task = task
    @language = language
    @sdk = sdk
    @exception_use_openai_preview_sdk = exceptions[:use_openai_preview_sdk]&.include?(@model_name) || false
    @exception_hide_java_assistant = exceptions[:hide_java_assistant]&.include?(@model_name) || false
    @assistant_role = exceptions[:assistant_role]

    @top_p_value = parameters_as_template ? "{top_p}" : 1.0
    @temperature_value = parameters_as_template ? "{temperature}" : 1.0
    @max_tokens_value = parameters_as_template ? "{max_tokens}" : 1000
    @system_message_value = parameters_as_template ? "{system_message}" : "You are a helpful assistant."
  end

  def template_path
    "samples/#{@task}/#{@language}/#{@sdk}_sdk"
  end
end
