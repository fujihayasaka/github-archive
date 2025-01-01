# typed: strict
# frozen_string_literal: true

module Codespaces
  class CopilotWorkspaceConcurrencyLimitError < StandardError
    extend T::Sig

    sig { params(msg: String).void }
    def initialize(msg = "Limit of active Copilot Workspaces reached.")
      super
    end
  end
end
