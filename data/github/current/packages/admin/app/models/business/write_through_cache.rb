# typed: true
# frozen_string_literal: true

# Business::WriteThroughCache will return the last value of a call, then update the value in the background.
# It only works with Business public methods that return an array.
#
# This is an extension of the PassThroughCache class. The difference is it will update the cache in the background
# when the method is called.
#
# Example:
#   business = Business.find(1)
#   business.write_through_cache.get_and_update(:all_member_ids)
#
# The first time this is called, it will execute business.all_member_ids, store the results in the cache, then
# return the results.
#
# The second time this is called, it will update all_member_ids in the background, and return the cached results.
#
# The cache will be updated in the background every time this is called.
#
# This method provides speed, resiliency, and freshness. It does not reduce calls to the database.
# In order to reduce database calls, you must use the Business::PassThroughCache instead, which will provide
# speed, resiliency, and reduced database calls, at the cost of freshness.
#
class Business::WriteThroughCache
  include GitHub::Memoizer

  attr_reader :type, :business, :method, :args, :pluck

  sig { params(business: Business).void }
  def initialize(business)
    @business = business
  end

  # Returns the cached value of the method, and updates the cache in the background.
  # If the cache does not exist, it will execute the method, store the results in the cache, then return the results.
  sig { params(method: Symbol, args: T::Hash[T.untyped, T.untyped], type: Symbol, pluck: T.nilable(Symbol)).returns(T.nilable(T::Array[T.any(String, Integer)])) }
  def get_and_update(method, args = {}, type: :int, pluck: nil)
    @method = method
    @args = args
    @pluck = pluck
    return get_ids_from_method unless cache_enabled?

    cached_values = cache_store.get(cache_key, type)
    if cached_values
      GitHub.dogstats.increment("business.write_through_cache.count", tags: ["method:#{method}", "cache:hit"])
      BusinessUpdateWriteThroughCacheJob.perform_later(cache_key, business, method, args, type, pluck)
      return cached_values
    end
    GitHub.dogstats.increment("business.write_through_cache.count", tags: ["method:#{method}", "cache:miss"])
    values = get_ids_from_method
    return unless values

    cache_store.set(cache_key, values, type)
    values
  end

  # Updates the cache. If values are not provided, it will execute the method to get the values.
  sig { params(method: Symbol, args: T::Hash[T.untyped, T.untyped], type: Symbol, pluck: T.nilable(Symbol)).void }
  def update(method, args = {}, type:, pluck: nil)
    @method = method
    @args = args
    @pluck = pluck
    return unless cache_enabled?

    values = get_ids_from_method
    return unless values

    cache_store.set(cache_key, values, type)
  end

  private

  sig { returns(T.nilable(T::Array[T.any(String, Integer)])) }
  def get_ids_from_method
    result = business.send(method, **args)
    return nil if result.nil?

    return result.pluck(pluck) if pluck

    result.to_a
  end

  sig { returns(String) }
  def cache_key
    key_elements = [method.to_s, *args.map { |k, v| "#{k}-#{v}" }]
    key_elements << pluck if pluck

    key_elements.join(":")
  end

  sig { returns(T::Boolean) }
  memoize def cache_enabled?
    business.feature_flag_enabled?(:business_write_through_cache, default: false)
  end

  sig { returns(Business::PassThroughCache) }
  memoize def cache_store
    Business::PassThroughCache.new(
      "business",
      T.must(business.id), # Seed. This is a persistent cache, the seed needs to be unique to a business.
      disabled: GitHub.single_business_environment? || !cache_enabled?,
      expiration: 12.hours, # This cache will update when the method is called. It's safe to have a long expiration.
    )
  end
end
