# typed: strict
# frozen_string_literal: true

module RepositoryInsights
  module Cache
    extend GitHub::RemoteCache::ClientFactory

    REMOTE_CACHE_NAMESPACE = "repos_insights"

    sig { override.returns(GH::Domain::Base) }
    private_class_method def self.domain_instance
      RepositoryInsights.domain
    end

    sig { override.returns(String) }
    private_class_method def self.namespace
      REMOTE_CACHE_NAMESPACE
    end
  end
end
