# typed: strict
# frozen_string_literal: true

class CacheList
  sig { returns(T::Array[CacheEntry]) }
  attr_accessor :caches

  sig { returns(Integer) }
  attr_accessor :total_caches

  sig { params(caches: T::Array[CacheEntry], total_caches: Integer).void }
  def initialize(caches:, total_caches:)
    @caches = caches
    @total_caches = total_caches
  end

  sig { params(res: T.nilable(GitHub::Launch::Services::Artifactcache::ListCachesResponse)).returns(T.nilable(CacheList)) }
  def self.from_launch(res)
    return nil if res.nil?

    new(
      caches: res.caches.to_a.map { |cache| CacheEntry.from_launch(cache) },
      total_caches: res.total_caches
    )
  end

  sig { params(res: T.nilable(MonolithTwirp::ActionsResults::Core::V1::ListCachesResponse)).returns(T.nilable(CacheList)) }
  def self.from_results(res)
    return nil if res.nil?

    new(
      caches: res.caches.to_a.map { |cache| CacheEntry.from_results(cache) },
      total_caches: res.total_caches
    )
  end

  sig { params(res: T.nilable(MonolithTwirp::ActionsResults::Core::V1::DeleteCachesByKeyResponse)).returns(T.nilable(CacheList)) }
  def self.from_results_delete(res)
    return nil if res.nil?

    new(
      caches: res.caches.to_a.map { |cache| CacheEntry.from_results(cache) },
      total_caches: res.total_caches
    )
  end

  sig { params(res: T.nilable(GitHub::Launch::Services::Artifactcache::DeleteCachesByKeyResponse)).returns(T.nilable(CacheList)) }
  def self.from_launch_delete(res)
    return nil if res.nil?

    new(
      caches: res.caches.to_a.map { |cache| CacheEntry.from_launch(cache) },
      total_caches: res.total_caches
    )
  end
end
