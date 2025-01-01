# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::ClientTest < GitHub::TestCase
  setup do
    @test_config = {
      space: GitHub.contentful_customer_stories_space_id,
      access_token: GitHub.contentful_customer_stories_delivery_token,
      environment: GitHub.contentful_customer_stories_environment,
      entry_mapping: {
        "story" => Site::Contentful::CustomerStories::CustomerStory,
      }
    }
  end

  test "configuring a new client" do
    client = VCR.use_cassette("contentful/client-content-types-caching") do
      Site::Contentful::Client.new(@test_config)
    end

    assert client.is_a?(Contentful::Client)
    assert_equal @test_config[:space], client.configuration[:space]
    assert_equal @test_config[:access_token], client.configuration[:access_token]
    assert_equal @test_config[:environment], client.configuration[:environment]
    assert_equal @test_config[:entry_mapping], client.configuration[:entry_mapping]

    assert client.configuration[:raise_errors]
    refute client.configuration[:raise_for_empty_fields]
    # The test environment is configured to force auto dynamic entries
    assert_equal :auto, client.configuration[:dynamic_entries]
  end

  test "configuring a new client without forced auto dynamic entries" do
    original_dynamic_entries_config = GitHub.contentful_force_auto_dynamic_entries
    GitHub.contentful_force_auto_dynamic_entries = false

    # Warm the cache so we can test how a new client responds
    Contentful::ContentTypeCache.cache_set(@test_config[:space], "story", {})

    client = Site::Contentful::Client.new(@test_config)

    assert_equal :manual, client.configuration[:dynamic_entries]

    GitHub.contentful_force_auto_dynamic_entries = original_dynamic_entries_config
  end
end
