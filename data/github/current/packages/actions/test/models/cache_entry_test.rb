# typed: true
# frozen_string_literal: true

require "test_helper"

class CacheEntryTest < GitHub::TestCase
  setup do
    @id = 1
    @scope = "refs/heads/main"
    @key = "my-key"
    @version = SecureRandom.hex(12)
    @size = 1024
    @created_at = Google::Protobuf::Timestamp.new(seconds: 5.minutes.ago.to_i)
    @last_accessed_at = Google::Protobuf::Timestamp.new(seconds: 10.minutes.ago.to_i)

    @entry = CacheEntry.new(
      id: @id,
      scope: @scope,
      key: @key,
      version: @version,
      size: @size,
      created_at: @created_at,
      last_accessed_at: @last_accessed_at,
    )

    @launch_entry = GitHub::Launch::Services::Artifactcache::CacheEntry.new(
      id: @id,
      scope: @scope,
      key: @key,
      version: @version,
      size: @size,
      created: @created_at,
      lastAccessed: @last_accessed_at,
    )

    @results_entry = MonolithTwirp::ActionsResults::Core::V1::CacheEntry.new(
      id: @id,
      scope: @scope,
      key: @key,
      version: @version,
      size: @size,
      created_at: @created_at,
      last_accessed_at: @last_accessed_at,
    )
  end

  context "launch" do
    test "from" do
      assert_equal @entry, CacheEntry.from_launch(@launch_entry)
    end

    test "to" do
      assert_equal @launch_entry, @entry.to_launch
    end
  end

  context "results" do
    test "from" do
      assert_equal @entry, CacheEntry.from_results(@results_entry)
    end

    test "to" do
      assert_equal @results_entry, @entry.to_results
    end
  end
end
