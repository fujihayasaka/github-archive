# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module Prompt
      class OverallSummary < ::Copilot::Prompt::Base
        include GitHub::Memoizer
        include DiffHunkEncoder

        PromptItem = type_member { { fixed: DiffHunk } }

        sig do
          params(
            diff_hunks: T::Array[DiffHunk],
            pull_request: T.nilable(PullRequest),
            custom_prompt: T.nilable(String),
            current_user: T.nilable(User),
          ).returns(
            T::Array[OverallSummary]
          )
        end
        def self.prompts(diff_hunks:, pull_request: nil, custom_prompt: nil, current_user: nil)
          builder = ::Copilot::Prompt::Builder[OverallSummary, PromptItem].new(items: diff_hunks)
          builder.prompt_template = -> { new(pull_request: pull_request, custom_prompt: custom_prompt, current_user: current_user) }
          builder.prompts
        end

        sig { override.returns(T.nilable(PullRequest)) }
        attr_reader :pull_request

        sig { returns(T.nilable(String)) }
        attr_reader :custom_prompt

        sig { returns(T.nilable(User)) }
        attr_reader :current_user

        sig { params(pull_request: T.nilable(PullRequest), custom_prompt: T.nilable(String), current_user: T.nilable(User)).void }
        def initialize(pull_request: nil, custom_prompt: nil, current_user: nil)
          super()
          @pull_request = pull_request
          @custom_prompt = custom_prompt
          @current_user = current_user
        end

        sig { override.returns(T::Array[String]) }
        def stops
          []
        end

        sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
        def baseline_expected_response_tokens
          60..120
        end

        sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
        def per_item_expected_response_tokens
          90..180
        end

        sig { returns(Integer) }
        def max_tokens
          8_000
        end
      end
    end
  end
end
