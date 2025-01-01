# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesEnvironmentTest < GitHub::TestCase
  class TypeTest < GitHub::TestCase
    test "#cast_value when given a JSON string" do
      now = Time.now.iso8601
      json = {
        "id" => "some-id",
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => now,
        "connection" => { "foo" => "bar" }
      }
      value = Codespaces::Environment::Type.new.cast_value(json.to_json)
      assert_equal "some-id", value.id
      assert_equal Codespaces::Vscs::State::AVAILABLE, value.state
      assert_equal now, value.updated.iso8601
      assert_equal "bar", value["connection"]["foo"]
    end

    test "#cast_value when given a hash" do
      now = Time.now.iso8601
      json = {
        "id" => "some-id",
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => now,
        "connection" => { "foo" => "bar" }
      }
      value = Codespaces::Environment::Type.new.cast_value(json)
      assert_equal "some-id", value.id
      assert_equal Codespaces::Vscs::State::AVAILABLE, value.state
      assert_equal now, value.updated.iso8601
      # Ensure we're transforming keys properly
      assert_equal "bar", value["connection"]["foo"]
    end

    test "#cast_value when given a Codespaces::Environment" do
      env = Codespaces::Environment.from_json({
        "id" => "some-id",
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "friendlyName" => "name"
      })
      assert_equal env, Codespaces::Environment::Type.new.cast_value(env)
    end

    test "#serialize" do
      json = {
        "id" => "some-id",
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "friendlyName" => "name",
        "connection" => { "foo" => "bar" },
        "accessToken" => "supersecret"
      }
      value = Codespaces::Environment::Type.new.cast_value(json)
      serialized = Codespaces::Environment::Type.new.serialize(value)
      # Ensure we transform keys _back_ to camelCase
      assert_includes serialized, "friendlyName"
      # Ensure we do not serialize connection
      refute_includes serialized, "connection"
      refute_includes serialized, "accessToken"
    end
  end

  test "allows camelCase JSON keys" do
    json = {
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "skuDisplayName" => "cool"
    }
    env = Codespaces::Environment.from_json(json)
    assert_equal "cool", env.sku_display_name
  end

  test "allows snake_case JSON keys" do
    json = {
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "sku_display_name" => "cool"
    }
    env = Codespaces::Environment.from_json(json)
    assert_equal "cool", env.sku_display_name
  end

  test "allows hash access to all JSON attributes provided whether allow-listed or not" do
    json = {
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "connection" => { "foo" => "bar" },
      "unknownKeyHere" => "some-value"
    }
    env = Codespaces::Environment.from_json(json)
    assert_equal "some-id", env["id"]
    assert_equal Codespaces::Vscs::State::AVAILABLE, env["state"]
    assert_equal "some-value", env["unknownKeyHere"]
  end

  test "allows the entire JSON payload but filters from as_json" do
    json = {
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "unknownKeyHere" => "some-value"
    }
    env = Codespaces::Environment.from_json(json)
    assert_includes env.json, "unknownKeyHere"
    refute_includes env.as_json, "unknownKeyHere"
  end

  test "#==" do
    now = Time.now.iso8601
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => now,
      "connection" => { "foo" => "bar" }
    })

    same = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => now,
      "connection" => { "foo" => "bar" }
    })

    assert_equal env, same

    different = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::PROVISIONING,
      "updated" => now,
      "connection" => { "foo" => "bar" }
    })

    refute_equal env, different
  end

  test "#as_json transforms keys back to camelCase" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "skuName" => "basic",
      "friendly_name" => "name"
    })
    json = env.as_json
    assert_includes json, "skuName"
    assert_includes json, "friendlyName"
  end

  test "#as_json excludes connection" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "skuName" => "basic",
      "connection" => { "foo" => "bar" }
    })
    json = env.as_json
    assert_includes json, "skuName"
    refute_includes json, "connection"
  end

  test "#as_json supports only option" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "skuName" => "basic",
      "connection" => { "foo" => "bar" },
      "skuDisplayName" => "Premium"
    })
    json = env.as_json(only: ["state"])
    assert_includes json, "state"
    refute_includes json, "skuName"
    refute_includes json, "updated"
    refute_includes json, "connection"
    refute_includes json, "skuDisplayName"
  end

  test "#environment_json matches raw JSON" do
    json = {
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "superRandomKey" => "value"
    }.to_json
    assert_equal json, Codespaces::Environment.from_json(json).environment_json
  end

  test "#available?" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "connection" => { "foo" => "bar" }
    })
    assert env.available?

    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::PROVISIONING,
      "updated" => Time.now.iso8601,
      "connection" => { "foo" => "bar" }
    })
    refute env.available?
  end

  test "#has_connection?" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => Time.now.iso8601,
      "connection" => { "foo" => "bar" }
    })
    assert env.has_connection?

    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::PROVISIONING,
      "updated" => Time.now.iso8601,
    })
    refute env.has_connection?
  end

  test "#suspended?" do
    now = Time.now.iso8601
    shutdown_states = [Codespaces::Vscs::State::SHUTDOWN, Codespaces::Vscs::State::SHUTTING_DOWN]
    shutdown_states.each do |state|
      env = Codespaces::Environment.from_json({
        "id" => "some-id",
        "state" => state,
        "updated" => now,
      })
      assert env.suspended?
    end

    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "updated" => now
    })
    refute env.suspended?
  end

  test "git_status helpers don't break if git_status is nil" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE
    })
    assert_nothing_raised { env.current_branch }
  end

  test "#current_branch returns nil instead of empty string" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "git_status" => {
        "current_branch" => ""
      }
    })
    refute env.current_branch
  end

  test "#current_commit returns nil instead of empty string" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "git_status" => {
        "current_commit" => ""
      }
    })
    refute env.current_commit
  end

  test "#container_id returns nil instead of empty string" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
    })
    refute env.container_id
  end

  test "#container_id returns the container.id when present" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "container" => {
        "id" => "mock-id"
      }
    })
    assert_equal "mock-id", env.container_id
  end

  test "#allowed_port_privacy_settings returns nil" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
    })
    refute env.allowed_port_privacy_settings
  end

  test "#allowed_port_privacy_settings returns the runtimeConstraints.allowedPortPrivacySettings when present" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "runtimeConstraints" => {
        "allowedPortPrivacySettings" => %w[private public]
      }
    })
    assert_equal %w[private public], env.allowed_port_privacy_settings
  end

  test "#has_unpushed_changes? reads from gitStatus instead of old/deprecated root property" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "gitStatus" => {
        "ahead" => 0,
        "behind" => 0,
        "branch" => "master",
        "commit" => "f47fe26c1a1319a130e90d2d807f704074f754d5",
        "hasUnpushedChanges" => true,
        "hasUncommittedChanges" => true
      }
    })
    assert env.has_unpushed_changes?
  end

  test "#storage_utilization_in_kb returns the storageUtilizationInKb when present" do
    env = Codespaces::Environment.from_json({
      "id" => "some-id",
      "state" => Codespaces::Vscs::State::AVAILABLE,
      "storageUtilizationInKb" => 123456
    })
    assert_equal 123456, env.storage_utilization_in_kb
  end

  test "makes cascade token available" do
    json = {
      "accessToken" => "supersecret"
    }
    env = Codespaces::Environment.from_json(json)
    assert env.cascade_token
  end

  test "#blank? is true if the JSON is empty" do
    env = Codespaces::Environment.from_json("{}")
    assert env.blank?
  end
end
