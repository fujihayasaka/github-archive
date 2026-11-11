# typed: strict
# frozen_string_literal: true

module GitHubModels
  module Payloads
    class PromptInfo
      GitHubModelsPromptInfoPayload = T.type_alias do {
          content: T.nilable(String),
          path: T.nilable(String),
          ref: String,
          sha: String
        }
      end

      sig do
        params(
          path: T.nilable(String),
          ref: String,
          sha: String,
          content: T.nilable(String)
        ).void
      end
      def initialize(path:, ref:, sha:, content:)
        @path = path
        @ref = ref
        @sha = sha
        @content = content
      end

      sig { returns(GitHubModelsPromptInfoPayload) }
      def call
        {
          content: @content,
          path: @path,
          ref: @ref,
          sha: @sha
        }
      end
    end
  end
end
