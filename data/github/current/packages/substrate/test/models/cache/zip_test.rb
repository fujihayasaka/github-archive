# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/cache/zip"

class ZipCache
  include GitHub::Cache::Timid
  include GitHub::Cache::FakeAsync
  include GitHub::Cache::FakeConfig
  include GitHub::Cache::Zip
end

class GitHubCacheZipMixinTest < GitHub::TestCase
  setup do
    @cache = ZipCache.new
    @cache.allow = /.*/
  end

  def with_lowered_constants
    GitHub::Cache::Zip.stub_const(:MAX_UNZIPPED_SIZE, 10) do
      GitHub::Cache::Zip.stub_const(:MAX_ATTEMPT_CACHE_SIZE, 10_000) do
        yield
      end
    end
  end

  test "works with raw sets and gets" do
    with_lowered_constants do
      content = "some string"
      key = "raw-test"
      @cache.set(key, content)
      assert_equal content, @cache.get(key)
    end
  end

  test "works with raw async_sets and async_gets" do
    with_lowered_constants do
      content = "some string"
      key = "raw-test"
      @cache.async_set(key, content).sync
      assert_equal content, @cache.async_get(key).sync.value
    end
  end

  test "transparently zips sets over MAX_UNZIPPED_SIZE bytes" do
    with_lowered_constants do
      content = "some string" * GitHub::Cache::Zip::MAX_UNZIPPED_SIZE
      key = "raw-test2"
      @cache.set(key, content)
      assert_equal content, @cache.get(key)
    end
  end

  test "transparently zips async_sets over MAX_UNZIPPED_SIZE bytes" do
    with_lowered_constants do
      content = "some string" * GitHub::Cache::Zip::MAX_UNZIPPED_SIZE
      key = "raw-test2"
      @cache.async_set(key, content).sync
      assert_equal content, @cache.async_get(key).sync.value
    end
  end

  test "unzips those that need unzipping on get_multi" do
    with_lowered_constants do
      contents = (0...9).to_a.map { (1..100).to_a.map { ("a".."z").to_a.sample }.to_s }
      contents[4] = T.must(contents[4]) * (GitHub::Cache::Zip::MAX_UNZIPPED_SIZE + 1)
      contents[8] = T.must(contents[8]) * (GitHub::Cache::Zip::MAX_UNZIPPED_SIZE + 1)

      contents.each_with_index do |content, i|
        @cache.set("gibberish-#{i}", content)
      end

      keys = (0..9).to_a.map { |i| "gibberish-#{i}" }
      got = @cache.get_multi(keys)

      contents.each_with_index do |content, i|
        assert_equal content, got["gibberish-#{i}"]
      end
    end
  end

  test "unzips those that need unzipping on async_get_multi" do
    with_lowered_constants do
      contents = (0...9).to_a.map { (1..100).to_a.map { ("a".."z").to_a.sample }.to_s }
      contents[4] = T.must(contents[4]) * (GitHub::Cache::Zip::MAX_UNZIPPED_SIZE + 1)
      contents[8] = T.must(contents[8]) * (GitHub::Cache::Zip::MAX_UNZIPPED_SIZE + 1)

      contents.each_with_index do |content, i|
        @cache.async_set("gibberish-#{i}", content).sync
      end

      keys = (0..9).to_a.map { |i| "gibberish-#{i}" }
      got = @cache.async_get_multi(keys).sync

      contents.each_with_index do |content, i|
        assert_equal content, got["gibberish-#{i}"]
      end
    end
  end

  test "does actually try to cache when value is reasonable" do
    with_lowered_constants do
      @cache.expects(:zip_value).once
      @cache.set("some-key", "x" * (GitHub::Cache::Zip::MAX_ATTEMPT_CACHE_SIZE - 1))
    end
  end

  test "doesn't even try to cache when value is medium" do
    with_lowered_constants do
      @cache.expects(:zip_value).never
      @cache.set("some-key", "x" * (GitHub::Cache::Zip::MAX_ATTEMPT_CACHE_SIZE + 1))
    end
  end

  test "does actually try to cache when value is reasonable (async)" do
    with_lowered_constants do
      @cache.expects(:zip_value).once
      @cache.async_set("some-key", "x" * (GitHub::Cache::Zip::MAX_ATTEMPT_CACHE_SIZE - 1)).sync
    end
  end

  test "doesn't even try to cache when value is medium (async)" do
    with_lowered_constants do
      @cache.expects(:zip_value).never
      @cache.async_set("some-key", "x" * (GitHub::Cache::Zip::MAX_ATTEMPT_CACHE_SIZE + 1)).sync
    end
  end
end
