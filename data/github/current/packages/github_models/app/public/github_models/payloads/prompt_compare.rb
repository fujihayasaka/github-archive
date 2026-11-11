# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class PromptCompare
      # Keep in sync with `ReviewAppPayload` in ui/packages/github-models-repo/routes/prompt/types.ts
      GitHubModelsPromptComparePayload = T.type_alias do
        {
          inferenceUrl: String,
          restrictedModels: T::Array[String],
          repository: T::Hash[Symbol, T.untyped],
          commitInfo: T::Hash[Symbol, T.untyped],
          improvedSysPromptModel: T.nilable(DefaultAndCustomModels::Types::Model),
          pull: {
            number: Integer,
            title: String,
          },
          basePrompt: PromptInfo,
          headPrompt: PromptInfo
        }
      end

      sig do
        params(
          models_user: GitHubModels::User,
          repository: T::Hash[Symbol, T.untyped],
          improved_sys_prompt_model: T.nilable(DefaultAndCustomModels::Types::Model),
          pull_request_number: Integer,
          pull_request_title: String,
          base_prompt: PromptInfo,
          head_prompt: PromptInfo,
          commit_info: T::Hash[Symbol, T.untyped],
          inference_url: String,
        ).void
      end
      def initialize(
        models_user:,
        repository:,
        improved_sys_prompt_model:,
        pull_request_number:,
        pull_request_title:,
        base_prompt:,
        head_prompt:,
        commit_info:,
        inference_url:
      )
        @models_user = models_user
        @repository = repository
        @improved_sys_prompt_model = improved_sys_prompt_model
        @pull_request_number = pull_request_number
        @pull_request_title = pull_request_title
        @base_prompt = base_prompt
        @head_prompt = head_prompt
        @commit_info = commit_info
        @inference_url = inference_url
      end

      sig { returns(GitHubModelsPromptComparePayload) }
      def call
        {
          inferenceUrl: @inference_url,
          restrictedModels: @models_user.restricted_models,
          improvedSysPromptModel: @improved_sys_prompt_model,
          repository: @repository,
          commitInfo: @commit_info,
          pull: {
            number: @pull_request_number,
            title: @pull_request_title,
          },
          basePrompt: @base_prompt,
          headPrompt: @head_prompt
        }
      end
    end
  end
end
