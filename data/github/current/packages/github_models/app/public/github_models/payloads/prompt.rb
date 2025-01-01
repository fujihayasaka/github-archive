# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class Prompt
      # TODO: Move to packages/github_models/app/public/github_models/types.rb
      # https://github.com/github/github/pull/365583#discussion_r1983960125
      GitHubModelsPromptPayload = T.type_alias do
        {
          inferenceUrl: String,
          restrictedModels: T::Array[String],
          improvedSysPromptModel: T.nilable(GitHubModels::Types::Model),
          prompt: T.nilable(String),
          promptPath: T.nilable(String),
          promptRef: T.nilable(String),
          repository: T::Hash[Symbol, T.untyped],
        }
      end

      include OcticonsHelper
      include GitHub::Memoizer

      sig { returns(T.nilable(::User)) }
      attr_reader :current_user

      sig do
        params(
          current_user: T.nilable(::User),
          improved_sys_prompt_model: T.nilable(GitHubModels::Types::Model),
          prompt: T.nilable(String),
          prompt_path: T.nilable(String),
          prompt_ref: T.nilable(String),
          repository: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        current_user:,
        improved_sys_prompt_model:,
        prompt:,
        prompt_path:,
        prompt_ref:,
        repository:
      )
        @current_user = current_user
        @improved_sys_prompt_model = improved_sys_prompt_model
        @prompt = prompt
        @prompt_path = prompt_path
        @prompt_ref = prompt_ref
        @repository = repository
      end

      sig { returns(GitHubModelsPromptPayload) }
      def call
        github_models_user = GitHubModels::User.new(user: @current_user)
        {
          inferenceUrl: github_models_user.playground_url,
          restrictedModels: github_models_user.restricted_models,
          improvedSysPromptModel: @improved_sys_prompt_model,
          prompt: @prompt,
          promptPath: @prompt_path,
          promptRef: @prompt_ref,
          repository: @repository,
        }
      end
    end
  end
end
