# frozen_string_literal: true
# typed: true

require "test_helper"
require "faraday"

require "vexi/builders/adapter_builder"
require "vexi/configuration"

class AdapterBuilderTest < Minitest::Test
  class TestAdapter
    include Vexi::Adapter

    def adapter_name; "test_adapter" end
    def check_actors_on_nonembedded_segments(_segments, _actors); end
    def get_feature_flags(_names); end
    def get_segments(_names); end
  end

  def setup
    @config = Vexi::Configuration.new
    @adapter_builder = Vexi::Builders::AdapterBuilder.new(@config)
  end

  def teardown
    ENV.delete("KUBE_CLUSTER_STAMP")
  end

  def test_custom
    adapter = TestAdapter.new

    @adapter_builder.custom(adapter)

    assert_equal(adapter, @config.adapter)
  end

  def test_in_memory
    mode = Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault

    @adapter_builder.in_memory(mode, exception_feature_flags: [])

    assert_equal("in_memory", @config.adapter.adapter_name)
  end

  def test_file
    feature_flags_base_path = "path/to/features"
    segments_base_path = "path/to/segments"

    @adapter_builder.file(feature_flags_base_path, segments_base_path)

    assert_equal("json_file", @config.adapter.adapter_name)
  end
end
