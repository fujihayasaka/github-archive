# typed: strict
# frozen_string_literal: true

module Issues
  module Cache
    extend GitHub::RemoteCache::ClientFactory

    REMOTE_CACHE_NAMESPACE = "issues"

    sig { override.returns(GH::Domain::Base) }
    private_class_method def self.domain_instance
      Issues.domain
    end

    sig { override.returns(String) }
    private_class_method def self.namespace
      REMOTE_CACHE_NAMESPACE
    end
  end
end
