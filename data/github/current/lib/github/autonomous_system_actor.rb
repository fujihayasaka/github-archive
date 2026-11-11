# typed: strict
# frozen_string_literal: true

module GitHub
  # AutonomousSystemActor is used to toggle feature flags by the autonomous
  # system (AS) of a request, which GLB passes for untrusted requests in the
  # `X-AS` header.
  class AutonomousSystemActor
    include GitHub::VexiActor

    sig { override.returns(String) }
    attr_reader :vexi_id

    alias :to_s :vexi_id

    sig { params(request: ActionDispatch::Request).returns(AutonomousSystemActor) }
    def self.for(request)
      new(request.headers["X-AS"])
    end

    sig { params(as: T.nilable(String)).void }
    def initialize(as)
      @as = as
      @vexi_id = T.let("X-AS:#{as || "not-set"}", String)
    end
  end
end
