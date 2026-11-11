# typed: true

# Shim for Copilot::AgentSession adding the polymorphic agent typing and the
# typed signature for the triggered_for_pr scope. Tapioca-generated DSL covers
# column accessors and the bare scope method; this shim adds info Tapioca
# can't infer.
module Copilot
  class AgentSession < ApplicationRecord::Copilot
    sig { returns(T.any(::Integration, ::OauthApplication)) }
    def agent; end

    sig do
      params(
        repository_id: T.any(Integer, ::Repository),
        pull_request_id: Integer,
        head_ref: String,
      ).returns(T.untyped)
    end
    def self.triggered_for_pr(repository_id:, pull_request_id:, head_ref:); end
  end
end
