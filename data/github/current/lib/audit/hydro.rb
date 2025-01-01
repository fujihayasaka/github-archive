# typed: true
# frozen_string_literal: true

module Audit
  module Hydro
    autoload :EventForwarder, "audit/hydro/event_forwarder"
    autoload :Hydrator, "audit/hydro/hydrator"

    DEFAULT_SHARD = "User;0"
  end
end
