# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../../../../app/models/site/k_v"

class Site::Contentful::FakePage < Site::Contentful::Page
  sig { override.returns(String) }
  def cache_key
    "site.contentful.pages.fake/v1"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    { stories: Array.new(5) }
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    # super simple validation to ensure all the pieces are
    # correctly connected
    raise if data[:stories].size != 5
  end
end

class Site::Contentful::SkipCache < Site::Contentful::FakePage
  def skip_cache?
    true
  end
end

class Site::Contentful::BlankPage < Site::Contentful::Page
  sig { override.returns(String) }
  def cache_key
    "site.contentful.pages.blank/v1"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    {}
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    raise "Blank pages shouldn't validate!"
  end
end

class Site::Contentful::LongCacheKey < Site::Contentful::Page
  sig { override.returns(String) }
  def cache_key
    "a" * 256
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    { stories: Array.new(5) }
  end
end

class Site::Contentful::InvalidPage < Site::Contentful::Page
  sig { override.returns(String) }
  def cache_key
    "site.contentful.pages.invalid/v1"
  end

  sig { override.returns(JsonLikeType) }
  def fetch_data_from_contentful
    { stories: Array.new(5) }
  end

  sig { override.params(data: JsonLikeType).void }
  def validate!(data)
    raise "No matter what, this validation will fail!"
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
      Site::KV.store.set(subject.cache_key, data)

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
      Site::KV.store.set(subject.cache_key, data)

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
      Site::KV.store.set(subject.cache_key, data)

      subject.revalidate

      result = subject.view_data

      assert_equal 5, result[:stories].count
    end

    test "clears the cache if there is new data that exceeds the cache max size" do
      subject = Site::Contentful::FakePage.new

      data = Zlib::Deflate.deflate(JSON.generate({ stories: Array.new(1) }))
      Site::KV.store.set(subject.cache_key, data)

      Site::KV.store.stubs(:set).once.raises(GitHub::KV::ValueLengthError)

      # We use the :reading role to simulate a scenario where the application reads from
      # the replica by default (typically during HTTP GET requests).
      ActiveRecord::Base.connected_to(role: :reading) do
        subject.revalidate
      end

      assert_nil Site::KV.store.get(subject.cache_key).value { raise "Expected GitHub.kv to be available" }
    end

    test "does not save anything in the cache if the key does not exist yet and the data is blank" do
      subject = Site::Contentful::BlankPage.new

      subject.revalidate

      assert_equal false, Site::KV.store.exists(subject.cache_key).value { raise "Expected GitHub.kv to be available" }
    end

    test "does not break if the cache key is extremely long" do
      subject = Site::Contentful::LongCacheKey.new

      assert_nothing_raised do
        subject.revalidate
      end
    end

    context "handling validation" do
      test "considers the data to be valid if it is blank" do
        enable_feature_flag(:contentful_response_validation)

        subject = Site::Contentful::BlankPage.new

        subject.expects(:save_page_data_in_cache).with({}).once

        subject.revalidate
      end

      test "does not update the cache if the data is invalid" do
        enable_feature_flag(:contentful_response_validation)

        subject = Site::Contentful::InvalidPage.new

        subject.expects(:save_page_data_in_cache).never

        subject.revalidate
      end

      test "updates the cache if the data is valid" do
        enable_feature_flag(:contentful_response_validation)

        subject = Site::Contentful::FakePage.new

        subject.expects(:save_page_data_in_cache).once

        subject.revalidate
      end
    end
  end
end
