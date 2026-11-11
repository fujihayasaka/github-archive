# typed: strict
# frozen_string_literal: true

module GitHubUI
  class Cache
    MANIFEST_CACHE = LruRedux::Cache.new(5)
    PREVIEW_MANIFEST_CACHE = LruRedux::TTL::Cache.new(20, PREVIEW_TTL)

    SHA_FALLBACK = T.let({}, T::Hash[Target, SHAFallbackEntry])
    FALLBACK_CACHE_TTL = T.let(30.seconds, T.any(Integer, ActiveSupport::Duration))

    sig { params(target: Target, sha: SHA).void }
    def self.update_sha_fallback(target:, sha:)
      SHA_FALLBACK[target] = { sha: sha, expires_at: Time.now + FALLBACK_CACHE_TTL }
    end

    sig { params(sha: SHA, target: Target).returns(T.nilable(ManifestData)) }
    def self.get_manifest(sha:, target:)
      if target == TARGETS[:preview]
        PREVIEW_MANIFEST_CACHE[sha]
      else
        MANIFEST_CACHE[sha]
      end
    end

    sig { params(sha: SHA, manifest: ManifestData, target: Target).void }
    def self.set_manifest(sha:, manifest:, target:)
      if target == TARGETS[:preview]
        PREVIEW_MANIFEST_CACHE[sha] = manifest
      else
        MANIFEST_CACHE[sha] = manifest
      end
    end

    sig { params(target: String).returns(T.nilable(SHA)) }
    def self.get_fallback_sha(target:)
      entry = SHA_FALLBACK[target]

      # Use the fallback if it's present and not expired
      if entry.present? && entry[:expires_at] > Time.now
        return entry[:sha]
      end

      # Otherwise remove the fallback and return nil
      SHA_FALLBACK.delete(target)
      nil
    end

    sig { void }
    def self.clear
      MANIFEST_CACHE.clear
      PREVIEW_MANIFEST_CACHE.clear
      SHA_FALLBACK.clear
    end
  end
end
