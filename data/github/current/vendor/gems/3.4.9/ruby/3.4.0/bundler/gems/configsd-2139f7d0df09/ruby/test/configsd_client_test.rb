# frozen_string_literal: true

require "test_helper"
require "configs"
require "json"

class ConfigsClientTest < Minitest::Test
  def setup
    @base_url = "https://configsd.github.com"
    @connection = Faraday.new(url: @base_url)
    @client = Configs::Client.new(@connection)
  end

  def test_resolve_configs_by_target_with_symbol
    client = Configs::Client.new(stub_successful_faraday_response)

    result = client.resolve_configs_by_target(
      target_id: 12345,
      target_type: :Repository
    )

    assert_instance_of Hash, result
  end

  def test_resolve_configs_by_target_with_integer
    client = Configs::Client.new(stub_successful_faraday_response)

    result = client.resolve_configs_by_target(
      target_id: 12345,
      target_type: :Repository
    )

    assert_instance_of Hash, result
  end

  def test_resolve_configs_by_target_with_invalid_type
    client = Configs::Client.new(stub_successful_faraday_response)

    error = assert_raises(ArgumentError) do
      client.resolve_configs_by_target(
        target_id: 12345,
        target_type: :InvalidType
      )
    end

    assert_match(/Unknown target type/, error.message)
  end

  def test_resolve_configs_by_target_handles_failed_response
    client = Configs::Client.new(stub_failed_faraday_response)

    error = assert_raises(Configs::RpcError) do
      client.resolve_configs_by_target(
        target_id: 12345,
        target_type: :Repository
      )
    end

    assert_match(/RPC failed with status internal/, error.message)
  end

  def test_resolve_configs_by_target_makes_correct_request
    request_body = nil

    # Create a connection that captures the request body
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTarget") do |env|
        request_body = env[:body]
        response_proto = Configs::Twirp::ResolveConfigsByTargetResponse.new(
          configs: Configs::Twirp::ResolvedConfigs.new(
            configs: {
              "config1" => Configs::Twirp::Config.new(
                name: "config1",
                value: "value1",
                target: Configs::Twirp::ConfigTarget.new(id: 12345, type: :Repository),
                created_at: { seconds: 1625097600, nanos: 0 },
                updated_at: { seconds: 1625184000, nanos: 0 }
              )
            }
          )
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetResponse.encode(response_proto)
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    client.resolve_configs_by_target(
      target_id: 12345,
      target_type: :Repository
    )

    assert request_body
    # Verify the request was encoded properly
    decoded_request = Configs::Twirp::ResolveConfigsByTargetRequest.decode(request_body)
    assert_equal 12345, decoded_request.target.id
    assert_equal :Repository, decoded_request.target.type # Repository enum value is 0
  end

  def test_resolve_configs_by_target_with_owners_success
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetWithOwners") do |env|
        response_proto = Configs::Twirp::ResolveConfigsByTargetResponse.new(
          configs: Configs::Twirp::ResolvedConfigs.new(
            configs: {
              "config1" => Configs::Twirp::Config.new(
                name: "config1",
                value: "value1",
                target: Configs::Twirp::ConfigTarget.new(id: 12345, type: :Repository),
                created_at: { seconds: 1625097600, nanos: 0 },
                updated_at: { seconds: 1625184000, nanos: 0 }
              )
            }
          )
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetResponse.encode(response_proto)
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    result = client.resolve_configs_by_target_with_owners(repo_id: 12345)

    assert_instance_of Hash, result
    assert_equal 1, result.size
    assert_equal "config1", result["config1"].name
    assert_equal "value1", result["config1"].value
  end

  def test_resolve_configs_by_target_with_owners_with_multiple_ids
    request_body = nil

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetWithOwners") do |env|
        request_body = env[:body]
        response_proto = Configs::Twirp::ResolveConfigsByTargetResponse.new(
          configs: Configs::Twirp::ResolvedConfigs.new(configs: {})
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetResponse.encode(response_proto)
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    client.resolve_configs_by_target_with_owners(
      repo_id: 123,
      owner_id: 456,
      business_id: 789
    )

    assert request_body
    decoded_request = Configs::Twirp::ResolveConfigsByTargetWithOwnersRequest.decode(request_body)
    assert_equal 123, decoded_request.target.repo_id
    assert_equal 456, decoded_request.target.owner_id
    assert_equal 789, decoded_request.target.business_id
  end

  def test_resolve_configs_by_target_with_owners_handles_error
    client = Configs::Client.new(stub_failed_faraday_response_with_owners)

    error = assert_raises(Configs::RpcError) do
      client.resolve_configs_by_target_with_owners(repo_id: 12345)
    end

    assert_match(/RPC failed with status internal/, error.message)
  end

  def test_resolve_configs_by_targets_with_owners_success
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetsWithOwners") do |env|
        # Build response with nested structure
        resolved_configs_by_id = Configs::Twirp::ResolvedConfigsById.new(
          configs_by_id: {
            123 => Configs::Twirp::ResolvedConfigs.new(
              configs: {
                "config1" => Configs::Twirp::Config.new(
                  name: "config1",
                  value: "value1",
                  target: Configs::Twirp::ConfigTarget.new(id: 123, type: :Repository),
                  created_at: { seconds: 1625097600, nanos: 0 },
                  updated_at: { seconds: 1625184000, nanos: 0 }
                )
              }
            ),
            456 => Configs::Twirp::ResolvedConfigs.new(
              configs: {
                "config2" => Configs::Twirp::Config.new(
                  name: "config2",
                  value: "value2",
                  target: Configs::Twirp::ConfigTarget.new(id: 456, type: :Repository),
                  created_at: { seconds: 1625097600, nanos: 0 },
                  updated_at: { seconds: 1625184000, nanos: 0 }
                )
              }
            )
          }
        )

        response_proto = Configs::Twirp::ResolveConfigsByTargetsWithOwnersResponse.new(
          configs_by_type: {
            0 => resolved_configs_by_id # 0 = Repository
          }
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetsWithOwnersResponse.encode(response_proto)
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    result = client.resolve_configs_by_targets_with_owners(
      targets: [
        { repo_id: 123 },
        { repo_id: 456 }
      ]
    )

    assert_instance_of Hash, result
    assert_equal 1, result.size # One target type (Repository = 0)
    assert result["Repository"] # Repository configs exist
    assert_equal 2, result["Repository"].to_h.size # Two target IDs
    assert result["Repository"][123] # First repo configs
    assert result["Repository"][456] # Second repo configs
    assert_equal "config1", result["Repository"][123]["config1"].name
    assert_equal "config2", result["Repository"][456]["config2"].name
  end

  def test_resolve_configs_by_targets_with_owners_empty_targets
    client = Configs::Client.new(stub_successful_faraday_response)

    error = assert_raises(ArgumentError) do
      client.resolve_configs_by_targets_with_owners(targets: [])
    end

    assert_match(/At least one target must be provided/, error.message)
  end

  def test_resolve_configs_by_targets_with_owners_nil_targets
    client = Configs::Client.new(stub_successful_faraday_response)

    error = assert_raises(ArgumentError) do
      client.resolve_configs_by_targets_with_owners(targets: nil)
    end

    assert_match(/At least one target must be provided/, error.message)
  end

  def test_resolve_configs_by_targets_with_owners_makes_correct_request
    request_body = nil

    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetsWithOwners") do |env|
        request_body = env[:body]
        response_proto = Configs::Twirp::ResolveConfigsByTargetsWithOwnersResponse.new(
          configs_by_type: {}
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetsWithOwnersResponse.encode(response_proto)
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    client.resolve_configs_by_targets_with_owners(
      targets: [
        { repo_id: 123, owner_id: 456 },
        { business_id: 789 }
      ]
    )

    assert request_body
    decoded_request = Configs::Twirp::ResolveConfigsByTargetsWithOwnersRequest.decode(request_body)
    assert_equal 2, decoded_request.targets.size
    assert_equal 123, decoded_request.targets[0].repo_id
    assert_equal 456, decoded_request.targets[0].owner_id
    assert_equal 789, decoded_request.targets[1].business_id
  end

  def test_resolve_configs_by_targets_with_owners_handles_error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetsWithOwners") do |env|
        error_body = {
          code: "internal",
          msg: "Internal Server Error"
        }.to_json
        [
          500,
          { "Content-Type" => "application/json" },
          error_body
        ]
      end
    end

    stub_connection = Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end

    client = Configs::Client.new(stub_connection)

    error = assert_raises(Configs::RpcError) do
      client.resolve_configs_by_targets_with_owners(targets: [{ repo_id: 123 }])
    end

    assert_match(/RPC failed with status internal/, error.message)
  end

  private

  def stub_successful_faraday_response
    # Create a connection with a test adapter
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTarget") do |env|
        response_proto = Configs::Twirp::ResolveConfigsByTargetResponse.new(
          configs: Configs::Twirp::ResolvedConfigs.new(configs: {})
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetResponse.encode(response_proto)
        ]
      end
    end

    Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end
  end

  def stub_failed_faraday_response
    # Create a connection with a test adapter that returns a Twirp error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTarget") do |env|
        error_body = {
          code: "internal",
          msg: "Internal Server Error"
        }.to_json
        [
          500,
          { "Content-Type" => "application/json" },
          error_body
        ]
      end
    end

    Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end
  end

  def stub_failed_faraday_response_with_owners
    # Create a connection with a test adapter that returns a Twirp error
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/configs.Configs/ResolveConfigsByTargetWithOwners") do |env|
        error_body = {
          code: "internal",
          msg: "Internal Server Error"
        }.to_json
        [
          500,
          { "Content-Type" => "application/json" },
          error_body
        ]
      end
    end

    Faraday.new(url: @base_url) do |conn|
      conn.adapter :test, stubs
    end
  end

  def build_mock_faraday_response
    # Create a connection with a test adapter for capturing the request
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/twirp/configs.Configs/ResolveConfigsByTarget") do |env|
        response_proto = Configs::Twirp::ResolveConfigsByTargetResponse.new(
          configs: Configs::Twirp::ResolvedConfigs.new(configs: {})
        )
        [
          200,
          { "Content-Type" => "application/protobuf" },
          Configs::Twirp::ResolveConfigsByTargetResponse.encode(response_proto)
        ]
      end
    end

    stubs
  end
end
