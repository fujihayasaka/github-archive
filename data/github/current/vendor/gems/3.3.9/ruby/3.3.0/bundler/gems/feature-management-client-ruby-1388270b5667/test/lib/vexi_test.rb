# frozen_string_literal: true
# typed: true

require "test_helper"

class VexiTest < Minitest::Test
  include MockFactory

  def setup
    # Reset thread-local client before each test
    Thread.current[:vexi_instance] = nil
    # Reset vexi configuration before each test
    Vexi.instance_variable_set(:@configuration, nil)

    @adapter = create_mock_adapter
    @cache = create_mock_cache
    @feature_flag_service = create_mock_feature_flag_service
    @segment_service = create_mock_segment_service
    @instrumenter = Vexi::Observability::Notification.new
    @custom_gate_evaluator = create_mock_custom_gates_evaluator

    # These services are initialized by Vexi.build()
    Vexi::Services::FeatureFlagService.stubs(:new).returns(@feature_flag_service)
    Vexi::Services::SegmentService.stubs(:new).returns(@segment_service)
    Vexi::Notifications.instrumenter = T.let(@instrumenter, Vexi::Observability::Notification)

    @vexi = Vexi.build do |builder|
      builder.adapter.custom(@adapter)
      builder.cache.custom(@cache, 30, 30)
      builder.custom_gates_evaluator.custom(@custom_gate_evaluator)
    end
  end

  def test_instance_returns_error_when_not_configured
    error = assert_raises(Vexi::Configuration::ConfigurationError) do
      Vexi.instance
    end

    assert_equal("Invalid configuration: adapter was not configured", error.message)
  end

  def test_instance_sets_thread_local_var_and_returns_client
    Vexi.configure { |b| b.adapter.custom(@adapter) }

    client = Vexi.instance
    assert_instance_of(Vexi::Client, client)

    assert_equal(client, Thread.current[:vexi_instance])
  end

  def test_configure_sets_thread_local_variable
    Vexi.configure { |b| b.adapter.custom(@adapter) }

    assert_equal(@adapter, Vexi.configuration.adapter)
    refute_nil Thread.current[:vexi_instance]
    assert_instance_of(Vexi::Client, Thread.current[:vexi_instance])
  end

  def test_configuration
    config = Vexi.configuration
    assert_instance_of(Vexi::Configuration, config)
  end

  # Test that enabled? returns false if feature flag service could not find feature flag
  def test_enabled_returns_false_if_feature_flag_does_not_exist
    @feature_flag_service.expects(:get).returns(nil)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?("does-not-exist")
  end

    # Test that enabled? returns true if feature flag service could find the flag and it's enabled
  def test_enabled_returns_true_if_feature_flag_is_enabled
    boolean_flag = Vexi::FeatureFlag.create_boolean_feature_flag("boolean-true", true)

    @feature_flag_service.expects(:get).returns(boolean_flag)
    Vexi::NonActorGateEvaluator.expects(:evaluate_boolean_gate).with(boolean_flag).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?("boolean-true")
  end
end
