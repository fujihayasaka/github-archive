# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module Prompt
      class OverallSummaryTemplate < ::Copilot::Prompt::Template
        PromptItem = type_member { { fixed: DiffHunk } }

        sig { returns(PullRequests::Copilot::Prompt::OverallSummary) }
        def prompt
          T.cast(super, PullRequests::Copilot::Prompt::OverallSummary)
        end

        sig { returns(T.nilable(Repository)) }
        def repository
          prompt.pull_request&.base_repository
        end
      end
    end
  end
end
