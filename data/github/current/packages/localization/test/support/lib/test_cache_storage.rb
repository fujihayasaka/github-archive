# typed: true
# frozen_string_literal: true

class TestCacheStorage
  def initialize
    @cache = {}
  end

  def read(key)
    @cache[key]
  end
  alias :get :read

  def write(key, value)
    @cache[key] = value
  end

  def exist?(key)
    @cache.key?(key)
  end

  def delete(key)
    @cache.delete(key)
  end
end
