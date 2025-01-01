# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  ResponseTimingMock = Struct.new(:status)

  context "cache token" do
    test "cached token gets returned and block is not run" do
      disable_feature_flag(:codespaces_force_no_cache_cascade_token)

      key_segments, type, cached_token = setup_cache
      client = Codespaces::Client.new
      block_ran = T.let(false, T::Boolean)
      refreshed_token = "refreshed_token"

      token = T.unsafe(client).send(:cache_token, *key_segments, type: type) do
        block_ran = true
        [refreshed_token, 1.day]
      end

      assert_equal cached_token, token
      assert !block_ran
    end

    test "cached token gets replaced with refreshed when forced with feature flag" do
      enable_feature_flag(:codespaces_force_no_cache_cascade_token)
      key_segments, type, cached_token = setup_cache
      client = Codespaces::Client.new
      refreshed_token = "refreshed_token"

      token = T.unsafe(client).send(:cache_token, *key_segments, type: type, force: false) do
        [refreshed_token, 1.day]
      end

      assert_equal refreshed_token, token
    end

    test "cached token gets replaced with refreshed when forced" do
      disable_feature_flag(:codespaces_force_no_cache_cascade_token)
      key_segments, type, cached_token = setup_cache
      client = Codespaces::Client.new
      refreshed_token = "refreshed_token"

      token = T.unsafe(client).send(:cache_token, *key_segments, type: type, force: true) do
        [refreshed_token, 1.day]
      end

      assert_equal refreshed_token, token
    end

    test "cache encrypted token when encrypted: true" do
      key_segments = %w(one two)
      type = "encrypted_test"
      client = Codespaces::Client.new
      plaintext_token = "plaintext_token"
      cache_key = Codespaces::TokenCache.generate_key(*key_segments, type: type)
      encryptor = RbNaCl::SimpleBox.from_secret_key(RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes))
      token = client.send(:cache_token, *key_segments, type: type, encrypted: true, encryptor: encryptor) do
        [plaintext_token, 1.day]
      end

      assert_equal plaintext_token, token
      refute_equal plaintext_token, Codespaces::Kv.store.get(cache_key).value { nil }
      assert_equal plaintext_token, encryptor.decrypt(Codespaces::Kv.store.get(cache_key).value { nil })
    end
  end

  context "timeouts" do
    test "with_timeouts temporarily sets the timeouts for all clients" do
      Codespaces::Client.with_timeouts("override") do
        assert_equal "override", Codespaces::Client.timeouts
        client = Codespaces::Client.new
        assert_equal "override", client.timeouts
      end
      assert_equal Codespaces::Client.default_timeouts, Codespaces::Client.timeouts
    end

    test "with_timeouts allows specific clients to override the default" do
      Codespaces::Client.with_timeouts("testing") do
        assert_equal "testing", Codespaces::Client.timeouts
        client = Codespaces::Client.new(timeouts: "override")
        assert_equal "override", client.timeouts
      end
    end

    test "timeouts work properly when no default present" do
      client = Codespaces::Client.new(timeouts: "timeouts")
      assert_equal "timeouts", client.timeouts
    end
  end

  context "retry_config" do
    test "with_retry_config temporarily sets the timeouts for all clients" do
      Codespaces::Client.with_retry_config("some other retry config") do
        assert_equal "some other retry config", Codespaces::Client.retry_config
        client = Codespaces::Client.new
        assert_equal "some other retry config", client.retry_config
      end
      assert_equal Codespaces::Client.default_retry_config, Codespaces::Client.retry_config
    end

    test "with_retry_config allows specific clients to overrirde the default" do
      Codespaces::Client.with_retry_config("testing retry config") do
        assert_equal "testing retry config", Codespaces::Client.retry_config
        client = Codespaces::Client.new(retry_config: "some other retry config")
        assert_equal "some other retry config", client.retry_config
      end
    end

    test "retry_config works properly when no default present" do
      client = Codespaces::Client.new(retry_config: "retry config")
      assert_equal "retry config", client.retry_config
    end
  end

  context "with_response_timing" do
    test "times the specified dogstat with response status and passed tags" do
      assert_dogstats_distribution(0, "codespaces.client.generic_response.latency")
      client = Codespaces::Client.new
      client.send(:with_response_timing, "codespaces.client.generic_response", tags: ["foo:bar"]) do
        ResponseTimingMock.new(status: 404)
      end
      assert_dogstats_distribution(1, "codespaces.client.generic_response.latency", tags: ["foo:bar", "status:404", "timeout:false"])
    end

    test "detects a timeout" do
      assert_dogstats_distribution(0, "codespaces.client.generic_response.latency")
      client = Codespaces::Client.new
      assert_raises(Faraday::TimeoutError) do
        client.send(:with_response_timing, "codespaces.client.generic_response", tags: ["foo:bar"]) do
          raise Faraday::TimeoutError
        end
      end
      assert_dogstats_distribution(1, "codespaces.client.generic_response.latency", tags: ["foo:bar", "timeout:true"])
    end
  end

  context "BadResponseError" do
    test "BadResponseError handles bare integers" do
      error = Codespaces::Client::BadResponseError.new("some error", 400, 4)
      assert_equal [4], error.error_codes
    end

    test "BadResponseError handles integer arrays" do
      error = Codespaces::Client::BadResponseError.new("some error", 400, [1, 2, 3])
      assert_equal [1, 2, 3], error.error_codes
    end

    test "BadResponseError handles strings" do
      error = Codespaces::Client::BadResponseError.new("some error", 400, "4")
      assert_equal [4], error.error_codes
    end

    test "BadResponseError handles bad data" do
      error = Codespaces::Client::BadResponseError.new("some error", 400, "some garbage data")
      assert_equal [], error.error_codes
      assert_equal "some garbage data", error.error_body
    end

    test "BadResponseError handles bad data that raises TypeError" do
      error = Codespaces::Client::BadResponseError.new("some error", 400, [[1, 2], [3, 4]])
      assert_equal [], error.error_codes
      assert_equal [[1, 2], [3, 4]], error.error_body
    end

    test "BadResponseError handles JSON" do
      error_body = { error: "some error" }
      error = Codespaces::Client::BadResponseError.new("some error", 400, error_body, rollup_components: nil)
      assert_equal [], error.error_codes
      assert_equal error_body, error.error_body
    end
  end

  context "RequestError" do
    test "accepts rollup components" do
      assert_equal ["caller"], Codespaces::Client::RequestError.new("", rollup_components: ["caller"]).rollup_components
    end

    test "uses a custom rollup if rollup components are provided" do
      refute_nil Codespaces::Client::RequestError.new("", rollup_components: ["caller"]).failbot_context[:rollup]
    end

    test "varies depending on the rollup components" do
      rollup1 = Codespaces::Client::RequestError.new("", rollup_components: ["caller-1"]).failbot_context[:rollup]
      rollup2 = Codespaces::Client::RequestError.new("", rollup_components: ["caller-2"]).failbot_context[:rollup]
      rollup3 = Codespaces::Client::RequestError.new("", rollup_components: %w[caller-1 caller-2]).failbot_context[:rollup]
      refute_equal rollup1, rollup2
      refute_equal rollup2, rollup3
      refute_equal rollup1, rollup3
    end

    test "does not customize rollup if no rollup components are provided" do
      assert_nil Codespaces::Client::RequestError.new("").failbot_context[:rollup]
    end
  end

  def setup_cache
    key_segments = %w(one two)
    type = "test"
    cache_key = "codespaces.token.#{type}.#{Digest::SHA256.hexdigest(key_segments.join)}"
    cached_token = "cached_token"
    expires_in = 1.day.from_now
    Codespaces::Kv.store.set(cache_key, cached_token, expires: expires_in)
    [key_segments, type, cached_token]
  end
end
