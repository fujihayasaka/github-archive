# typed: true
# frozen_string_literal: true

module Launch
  module Twirp
    class CacheClient < Launch::Twirp::BaseClient
      def list_caches(owner:, key: nil, ref: nil, per_page: 30, page: 1, sort: "last_accessed_at", direction: "desc")
        rpc(
          :ListCaches,
          repository_id: identity(owner),
          key:,
          scope: ref,
          sort:,
          direction:,
          page:,
          per_page:,
        )
      end

      def delete_caches_by_key(repo:, key:, ref: nil)
        rpc(
          :DeleteCachesByKey,
          repository_id: identity(repo),
          key:,
          scope: ref,
        )
      end

      def delete_cache_by_id(repo:, cache_id:)
        rpc(
          :DeleteCacheByID,
          repository_id: identity(repo),
          cache_id:,
        )
      end

      private

      def twirp_class
        GitHub::Launch::Services::Artifactcache::ArtifactCacheClient
      end
    end
  end
end
