# typed: strict
# frozen_string_literal: true

module AppSecurity
  module Cache
    extend GitHub::RemoteCache::ClientFactory

    REMOTE_CACHE_NAMESPACE = "app_security"

    sig { override.returns(GH::Domain::Base) }
    private_class_method def self.domain_instance
      AppSecurity.domain
    end

    sig { override.returns(String) }
    private_class_method def self.namespace
      REMOTE_CACHE_NAMESPACE
    end
  end
end
