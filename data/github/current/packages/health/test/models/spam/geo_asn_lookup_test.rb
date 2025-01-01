# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamGeoAsnLookupTest < GitHub::TestCase
  def geo_asn_lookup_stub(items)
    request_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/geo") do |_env|
        [200, {}, JSON.dump(items)]
      end
    end

    Faraday.new(url: "http://example.invalid") do |builder|
      builder.adapter(:test, request_stubs) { |_stub| }
    end
  end

  test ".is_tor_node? returns false in development" do
    mock_env = stub(development?: true)
    Rails.expects(:env).returns(mock_env)
    Spam::GeoAsnLookup.expects(:connection).never

    refute Spam::GeoAsnLookup.is_tor_node?("1.2.3.4")
  end

  test ".is_tor_node? returns false if tor_exit_node is false" do
    Spam::GeoAsnLookup.stubs(:connection).returns(geo_asn_lookup_stub([
      { "tor_exit_node" => false },
    ]))
    refute Spam::GeoAsnLookup.is_tor_node?("1.2.3.4")
  end

  test ".is_tor_node? returns true if tor_exit_node is true" do
    Spam::GeoAsnLookup.stubs(:connection).returns(geo_asn_lookup_stub([
      { "tor_exit_node" => true },
    ]))
    assert Spam::GeoAsnLookup.is_tor_node?("1.2.3.4")
  end

  test ".is_tor_node? returns false if address is not found" do
    Spam::GeoAsnLookup.stubs(:connection).returns(geo_asn_lookup_stub([]))
    refute Spam::GeoAsnLookup.is_tor_node?("1.2.3.4")
  end
end
