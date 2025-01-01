# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class RequestAccessTokenTest < GitHub::TestCase
    include DogstatsTestHelpers

    def make_token_request(cassette, **options, &block)
      VCR.use_cassette(cassette, **options) do
        yield
      end
    end

    context "EIS" do
      test "it responds with new access token then cache it when valid credentials supplied with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          assert_nil GitHub.cache.fetch(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY)
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_eis
          end
          assert_equal "A_VALID_TOKEN", response
          result = GitHub.cache.fetch(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY)
          box = RbNaCl::SimpleBox.from_secret_key(RequestAccessToken.sdn_authentication_token_key)
          result = box.decrypt(result)
          assert_equal "A_VALID_TOKEN", result
        end

        assert_equal 1, stats.increments("sdn_api.request_new_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_new_token.time")
      end

      test "gracefully handles RbNaCl::CryptoError when decrypting cached token fails" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          GitHub.cache.set(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY, "ja3rkfGF8WPNUt1wwb4bGzpuV8BG7bvZ", 1.minute)
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_eis
          end
          assert_equal response, ""
          assert_equal 1, stats.increments("sdn_eis_access_token.read.decrypt_error").count
        end
      end

      test "it responds with cached access_token it when valid credentials supplied with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          GitHub.cache.fetch(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY) do
            box = RbNaCl::SimpleBox.from_secret_key(RequestAccessToken.sdn_authentication_token_key)
            encrypted_token = box.encrypt("A_CACHED_TOKEN")
          end
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_eis
          end
          assert_equal "A_CACHED_TOKEN", response
        end

        assert_equal 1, stats.increments("sdn_api.request_cached_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_cached_token.time")
      end

      test "it responds with live token when encryption key is invalid with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        RequestAccessToken.stubs(:sdn_authentication_token_key).returns("")
        with_cache_enabled do
          assert_nil GitHub.cache.fetch(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY)
          response = make_token_request("trade_controls/sdn/valid_access_token", allow_playback_repeats: true) do
            RequestAccessToken.for_eis
          end
          assert_equal "A_VALID_TOKEN", response
          result = GitHub.cache.fetch(RequestAccessToken::EIS_AUTHENTICATION_TOKEN_CACHE_KEY)
          assert_nil result
        end

        assert_equal 1, stats.increments("sdn_api.request_new_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_new_token.time")
      end
    end

    context "LIVE API" do
      test "it responds with new access token then cache it when valid credentials supplied with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          assert_nil GitHub.cache.fetch(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY)
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_live_api
          end
          assert_equal "A_VALID_TOKEN", response
          result = GitHub.cache.fetch(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY)
          box = RbNaCl::SimpleBox.from_secret_key(RequestAccessToken.sdn_authentication_token_key)
          result = box.decrypt(result)
          assert_equal "A_VALID_TOKEN", result
        end

        assert_equal 1, stats.increments("sdn_api.request_new_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_new_token.time")
      end

      test "gracefully handles RbNaCl::CryptoError when decrypting cached token fails" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          GitHub.cache.set(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY, "ja3rkfGF8WPNUt1wwb4bGzpuV8BG7bvZ", 1.minute)
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_live_api
          end
          assert_equal response, ""
          assert_equal 1, stats.increments("sdn_live_access_token.read.decrypt_error").count
        end
      end

      test "it responds with cached access token when valid credentials supplied with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        with_cache_enabled do
          GitHub.cache.fetch(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY) do
            box = RbNaCl::SimpleBox.from_secret_key(RequestAccessToken::sdn_authentication_token_key)
            encrypted_token = box.encrypt("A_CACHED_TOKEN")
          end
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_live_api
          end
          assert_equal "A_CACHED_TOKEN", response
        end

        assert_equal 1, stats.increments("sdn_api.request_cached_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_cached_token.time")
      end

      test "it responds with live token when encryption key is invalid with logging" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        RequestAccessToken.stubs(:sdn_authentication_token_key).returns("")
        with_cache_enabled do
          assert_nil GitHub.cache.fetch(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY)
          response = make_token_request("trade_controls/sdn/valid_access_token") do
            RequestAccessToken.for_live_api
          end
          assert_equal "A_VALID_TOKEN", response
          result = GitHub.cache.fetch(RequestAccessToken::LIVE_AUTHENTICATION_TOKEN_CACHE_KEY)
          assert_nil result
        end

        assert_equal 1, stats.increments("sdn_api.request_new_token.success").count
        assert_dogstats_timing(1, "sdn_api.request_new_token.time")
      end
    end

    test "sdn_authentication_token_key is the same as encoded access token" do
      assert_equal GitHub.sdn_authentication_token_key.b, RequestAccessToken.sdn_authentication_token_key
    end

    test "it raises an error when unauthorized with invalid client secret with logging" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      client_secret_matcher = lambda do |request_1, request_2|
        invalid_client = "client_secret=INVALID"
        client_secret_1 = request_1.body.split("&")[1]
        client_secret_2 = request_2.body.split("&")[1]
        client_secret_2 == invalid_client && client_secret_2 == invalid_client
      end
      error = assert_raises SDNAuthenticationError do
        response = make_token_request("trade_controls/sdn/invalid_client_secret", match_requests_on: [client_secret_matcher]) do
          RequestAccessToken.for_eis
        end
      end
      assert_equal "Unauthorized due to Invalid client credentials", error.message

      expected_tags = [
        "reason: Invalid client secret is provided",
      ]
      assert_equal 1, stats.increments("sdn_api.request_new_token.failed").count
      assert_dogstats_timing(1, "sdn_api.request_new_token.time")
    end
  end
end
