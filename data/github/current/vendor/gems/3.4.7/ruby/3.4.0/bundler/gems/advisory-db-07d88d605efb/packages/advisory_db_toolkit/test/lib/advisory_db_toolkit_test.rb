require "test_helper"

class AdvisoryDbToolkitTest < Minitest::Test

  def test_not_to_set_cache_without_get_and_set_method
    cache = OpenStruct.new(get: nil)
    assert_raises(ArgumentError) { AdvisoryDBToolkit.cache = cache }

    cache = OpenStruct.new(set: nil)
    assert_raises(ArgumentError) { AdvisoryDBToolkit.cache = cache }
  end

  def test_set_cache_prefix_key
    cache_prefix_key = "test"
    AdvisoryDBToolkit.cache_prefix_key = cache_prefix_key

    assert_equal(cache_prefix_key, AdvisoryDBToolkit.cache_prefix_key)
  end

  def test_set_logger
    logger = Tools::Logger.new
    AdvisoryDBToolkit.logger = logger

    assert_equal(logger, AdvisoryDBToolkit.logger)
  end

  def test_not_to_set_logger_without_debug_and_info_method
    logger = OpenStruct.new(debug: nil)
    assert_raises(ArgumentError) { AdvisoryDBToolkit.logger = logger }

    logger = OpenStruct.new(info: nil)
    assert_raises(ArgumentError) { AdvisoryDBToolkit.logger = logger }

    logger = Tools::Logger.new
    AdvisoryDBToolkit.logger = logger # No error

    assert_equal(logger, AdvisoryDBToolkit.logger)
  end
end