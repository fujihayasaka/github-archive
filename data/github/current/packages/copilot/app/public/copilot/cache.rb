# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    extend GitHub::RemoteCache::ClientFactory

    REMOTE_CACHE_NAMESPACE = "policy_controls"

    sig { override.returns(GH::Domain::Base) }
    private_class_method def self.domain_instance
      CopilotDomain.domain
    end

    sig { override.returns(String) }
    private_class_method def self.namespace
      REMOTE_CACHE_NAMESPACE
    end
  end
end
