# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::FakePage < Site::Contentful::Page
  def cache_key
    "site.contentful.pages.fake/v1"
  end

  def fetch_data_from_contentful
    { stories: Array.new(5) }
  end
end

class Site::Contentful::SkipCache < Site::Contentful::FakePage
  def skip_cache?
    true
  end
end

class Site::Contentful::BlankPage < Site::Contentful::Page
  def cache_key
    "site.contentful.pages.blank/v1"
  end

  def fetch_data_from_contentful
    {}
  end
end

class Site::Contentful::LongCacheKey < Site::Contentful::Page
  def cache_key
    "a" * 256
  end

  def fetch_data_from_contentful
    { stories: Array.new(5) }
  end
end

class Site::Contentful::PageTest < GitHub::TestCase
  include ResiliencyHelpers

  setup do
    skip if GitHub.enterprise?
  end

  context "#view_data" do
    test "fetches the data from Contentful if there is not cached data" do
      subject = Site::Contentful::FakePage.new

      result = subject.view_data

      assert_equal 5, result[:stories].count
    end

    test "uses cached information if it is available" do
      subject = Site::Contentful::FakePage.new

      data = Zlib::Deflate.deflate(JSON.generate({ stories: Array.new(1) }))
      GitHub.kv.set(subject.cache_key, data) # rubocop:todo GitHub/DoNotUseGlobalKv

      result = subject.view_data

      assert_equal 1, result[:stories].count
    end

    test "saves the data into the cache if it was not there" do
      # Since some instance methods are memoized, we need to create multiple instances of FakePage
      # to verify this behavior.
      Site::Contentful::FakePage.new.view_data

      result = Site::Contentful::FakePage.new.tap { |page| page.expects(:fetch_data_from_contentful).never }.view_data

      assert_equal 5, result[:stories].count
    end

    test "skips fetching data from cache and revalidating if skip_cache? is true" do
      subject = Site::Contentful::SkipCache.new

      data = Zlib::Deflate.deflate(JSON.generate({ stories: Array.new(1) }))
      GitHub.kv.set(subject.cache_key, data) # rubocop:todo GitHub/DoNotUseGlobalKv

      subject.expects(:revalidate).never

      assert_equal 5, subject.view_data[:stories].count
    end

    test "fetches the data from Contentful if the cache is unavailable" do
      subject = Site::Contentful::FakePage.new

      prevent_connections_to(ApplicationRecord::Mysql5) do
        assert_equal 5, subject.view_data[:stories].count
      end
    end

    test "fetches the data from Contentful if the cache key is extremely long" do
      subject = Site::Contentful::LongCacheKey.new

      assert_equal 5, subject.view_data[:stories].count
    end
  end

  context "#revalidate" do
    test "refreshes the cache" do
      subject = Site::Contentful::FakePage.new

      data = Zlib::Deflate.deflate(JSON.generate({ stories: [] }))
      GitHub.kv.set(subject.cache_key, data) # rubocop:todo GitHub/DoNotUseGlobalKv

      subject.revalidate

      result = subject.view_data

      assert_equal 5, result[:stories].count
    end

    test "clears the cache if there is new data that exceeds the cache max size" do
      subject = Site::Contentful::FakePage.new

      data = Zlib::Deflate.deflate(JSON.generate({ stories: Array.new(1) }))
      GitHub.kv.set(subject.cache_key, data) # rubocop:todo GitHub/DoNotUseGlobalKv

      GitHub.kv.stubs(:set).once.raises(GitHub::KV::ValueLengthError) # rubocop:todo GitHub/DoNotUseGlobalKv

      # We use the :reading role to simulate a scenario where the application reads from
      # the replica by default (typically during HTTP GET requests).
      ActiveRecord::Base.connected_to(role: :reading) do
        subject.revalidate
      end

      assert_nil GitHub.kv.get(subject.cache_key).value { raise "Expected GitHub.kv to be available" } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "does not save anything in the cache if the key does not exist yet and the data is blank" do
      subject = Site::Contentful::BlankPage.new

      subject.revalidate

      assert_equal false, GitHub.kv.exists(subject.cache_key).value { raise "Expected GitHub.kv to be available" } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "does not break if the cache key is extremely long" do
      subject = Site::Contentful::LongCacheKey.new

      assert_nothing_raised do
        subject.revalidate
      end
    end
  end
end
