# typed: strict
# frozen_string_literal: true
module GhostPilot
  module Prompt
    class SummaryTemplate < ::Copilot::Prompt::Template
      PromptItem = type_member { { fixed: PullRequests::Copilot::DiffHunk } }

      sig { returns(GhostPilot::Prompt::Summary) }
      def prompt
        T.cast(super, GhostPilot::Prompt::Summary)
      end
    end
  end
end
