# typed: true

# Shim for Copilot::AgentSession to include the agent polymorphic association
module Copilot
  class AgentSession < ApplicationRecord::Copilot
    sig { returns(T.any(::Integration, ::OauthApplication)) }
    def agent; end
  end
end
