# frozen_string_literal: true

# TODO: Add typed: true, but have to figure out how to tell sorbet mock() exists (it's from Mocha::API)
module MockFactory
  def create_mock_adapter
    adapter = mock
    adapter.stubs(:is_a?).with do |type|
      type == Vexi::Adapter || type == T.nilable(Vexi::Adapter)
    end.returns(true)
    adapter.stubs(:adapter_name).returns("test_adapter")
    adapter
  end

  def create_mock_cache
    cache = mock
    cache.stubs(:is_a?).with do |type|
      type == Vexi::Cache || type == T.nilable(Vexi::Cache)
    end.returns(true)
    cache.stubs(:cache_name).returns("test_cache")
    cache
  end

  def create_mock_instrumenter
    instrumenter = mock
    instrumenter.stubs(:is_a?).with do |type|
      type == Vexi::Instrumenter || type == T.nilable(Vexi::Instrumenter)
    end.returns(true)
    instrumenter
  end

  def create_mock_feature_flag_service
    feature_flag_service = mock
    feature_flag_service.stubs(:is_a?).with do |type|
      type == Vexi::Services::FeatureFlagService ||
        type == T.nilable(Vexi::Services::FeatureFlagService) ||
        type == Vexi::AbstractEntityService ||
        type == T.nilable(Vexi::AbstractEntityService)
    end.returns(true)
    feature_flag_service
  end

  def create_mock_segment_service
    segment_service = mock
    segment_service.stubs(:is_a?).with do |type|
      type == Vexi::Services::SegmentService ||
        type == T.nilable(Vexi::Services::SegmentService) ||
        type == Vexi::AbstractEntityService ||
        type == T.nilable(Vexi::AbstractEntityService)
    end.returns(true)
    segment_service
  end

  def create_mock_custom_gates_evaluator
    custom_gates_evaluator = mock
    custom_gates_evaluator.stubs(:is_a?).with do |type|
      type == Vexi::CustomGatesEvaluator ||
        type == T.nilable(Vexi::CustomGatesEvaluator)
    end.returns(true)
    custom_gates_evaluator.stubs(:custom_gates_evaluator_name).returns("test_evaluator")
    custom_gates_evaluator
  end
end
