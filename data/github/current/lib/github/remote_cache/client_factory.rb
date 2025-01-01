# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    module ClientFactory
      extend T::Helpers
      abstract!

      sig { returns(GitHub::RemoteCache::Client) }
      def client
        return RemoteCache.create(namespace: namespace) unless registry = GH.context.remote_cache_registry

        registry[cache_client_key] ||= RemoteCache.create(namespace: namespace)
      end

      private

      sig { returns(String) }
      def cache_client_key
        "#{namespace}:#{domain_instance.object_id}"
      end

      sig { abstract.returns(GH::Domain::Base) }
      def domain_instance; end

      sig { abstract.returns(String) }
      def namespace; end
    end
  end
end
