# typed: true
# frozen_string_literal: true

if ENV["CI"]
  return
end

class GitHub::TestCase < GitHub::BasicTestCase
  # mimics GitHub caching strategy for tests
  def with_cache_enabled(_key_pattern = /.*/, &block)
    GitHub.stubs(:cache).returns(TestCacheStorage.new)
    block.call
  ensure
    GitHub.unstub(:cache)
  end

  def reset_flipper
    GitHub.flipper.reset
  end
end
