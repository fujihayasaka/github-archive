# typed: strict
# frozen_string_literal: true

module GhostPilot
  module Prompt
    # This is effecitvely a copy/paste from the Copilot4PullRequests prompt "OverallSummary"
    #   packages/copilot4prs/app/lib/pull_requests/copilot/prompt/overall_summary.rb.
    # This is not the complete prompt used by Ghost Pilot, which is the Web Component. Instead, this is
    # meant to create a summary of the changes, including a diff, with directions for how this diff can be used
    # to create a well-written pull request description.
    class Summary < ::Copilot::Prompt::Base
      include GitHub::Memoizer
      include PullRequests::Copilot::Prompt::DiffHunkEncoder

      PromptItem = type_member { { fixed: PullRequests::Copilot::DiffHunk } }

      sig do
        params(
          diff_hunks: T::Array[PullRequests::Copilot::DiffHunk],
        ).returns(
          T::Array[Summary]
        )
      end
      def self.prompts(diff_hunks:)
        builder = ::Copilot::Prompt::Builder[Summary, PromptItem].new(items: diff_hunks)
        builder.prompt_template = -> { new }
        builder.prompts
      end

      sig { override.returns(T.nilable(PullRequest)) }
      def pull_request
      end

      sig { override.returns(T::Array[String]) }
      def stops
        []
      end

      sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
      def baseline_expected_response_tokens
        5..40
      end

      sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
      def per_item_expected_response_tokens
        90..180
      end

      sig { returns(Integer) }
      def max_tokens
        2_000
      end
    end
  end
end
