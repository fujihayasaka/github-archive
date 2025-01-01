# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesSkusCacheTest < GitHub::TestCase
  test "raises on an invalid vscs_target or location" do
    assert_raises(ArgumentError) do
      Codespaces::Skus::Cache.get(:ppe, "Pluto")
    end

    assert_raises(ArgumentError) do
      Codespaces::Skus::Cache.get(:twilight_zone, "EastUs")
    end
  end

  test "retrieves an existing value from kv" do
    skus = [{ name: :standardLinux, transitions: [:basicLinux] }, { name: :basicLinux, transitions: [:standardLinux] }]
    Codespaces::Kv.store.set(Codespaces::Skus::Cache.key(:development, "WestEurope"), skus.to_json)
    cached_skus = Codespaces::Skus::Cache.get(:development, "WestEurope")

    assert_equal skus, cached_skus
  end

  test "is not case-sensitive for location" do
    skus = [{ name: :standardLinux, transitions: [:basicLinux] }, { name: :basicLinux, transitions: [:standardLinux] }]
    Codespaces::Kv.store.set(Codespaces::Skus::Cache.key(:development, "WestUs2"), skus.to_json)
    cached_skus = Codespaces::Skus::Cache.get(:development, "westus2")

    assert_equal skus, cached_skus
  end

  test "can fetch from VSO" do
    skus = [{ name: :standardLinux, transitions: [:basicLinux] }, { name: :basicLinux, transitions: [:standardLinux] }]
    Codespaces::Kv.store.set(Codespaces::Skus::Cache.key(:development, "WestUs2"), skus.to_json)

    cached_skus = Codespaces::Skus::Cache.get(:development, "WestUs2")
    assert_equal 2, cached_skus.length

    cached_skus = Codespaces::Skus::Cache.fetch_from_vscs(:development, "WestUs2")
    assert_equal 13, cached_skus.length
  end

  test "returns empty list of SKUs if we hit a response error from VSO when fetching" do
    Codespaces::AnonymousVscsClient.any_instance.stubs(:get_json).raises(Codespaces::Client::BadResponseError.new("bad combo"))
    cached_skus = Codespaces::Skus::Cache.fetch_from_vscs(:ppe, "EastUs")
    assert_equal [], cached_skus
  end

  test "leaves cache untouched if we hit an error from VSO when fetching" do
    skus = [{ name: :standardLinux, transitions: [:basicLinux] }, { name: :basicLinux, transitions: [:standardLinux] }]
    Codespaces::Kv.store.set(Codespaces::Skus::Cache.key(:ppe, "EastUs"), skus.to_json)

    Codespaces::AnonymousVscsClient.any_instance.stubs(:get_json).raises(Codespaces::Client::ConnectionFailed.new("blip"))
    fetched_skus = Codespaces::Skus::Cache.fetch_from_vscs(:ppe, "EastUs")

    cached_skus = Codespaces::Skus::Cache.get(:ppe, "EastUs")
    assert_equal skus.length, cached_skus.length
  end

  context "self#fetch_from_vscs" do
    test "stores the vscs_target and location in the Codespaces::Kv cache as the key" do
      assert_nil Codespaces::Kv.store.get("codespaces.vscs_skus.development.westus2").value { nil }

      fetched_skus = Codespaces::Skus::Cache.fetch_from_vscs(:development, "WestUs2")
      values = Codespaces::Kv.store.get("codespaces.vscs_skus.development.westus2").value { nil }

      refute_nil values
      assert_equal GitHub::JSON.parse(values).length, fetched_skus.length
    end

    test "stores the vscs_target, location and vscs_target_api_url in the Codespaces::Kv cache as the key" do
      assert_nil Codespaces::Kv.store.get("codespaces.vscs_skus.developmenthttps://online.dev.core.vsengsaas.visualstudio.com.westus2").value { nil }

      fetched_skus = Codespaces::Skus::Cache.fetch_from_vscs(:development, "WestUs2", nil, "https://online.dev.core.vsengsaas.visualstudio.com")
      values = Codespaces::Kv.store.get("codespaces.vscs_skus.developmenthttps://online.dev.core.vsengsaas.visualstudio.com.westus2").value { nil }

      refute_nil values
      assert_equal GitHub::JSON.parse(values).length, fetched_skus.length
    end
  end
end
