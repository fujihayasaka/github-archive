# typed: true
# frozen_string_literal: true

require "test_helper"

class ExperimentCacheTest < GitHub::TestCase
  test "is callable as rack middleware" do
    app = lambda { |env| env }
    cache = ExperimentCache.new(app)
    assert_equal :env, cache.call(:env)
  end

  test "fetch caches when enabled" do
    count = 0

    ExperimentCache.enable do
      2.times { ExperimentCache.fetch(:key) { count += 1 } }
    end

    assert_equal count, 1
  end

  test "fetch caches based on key" do
    ExperimentCache.enable do
      ExperimentCache.fetch(:first) { :first }
      ExperimentCache.fetch(:second) { :second }

      assert_equal :first, ExperimentCache.fetch(:first)
      assert_equal :second, ExperimentCache.fetch(:second)
    end
  end

  test "caches are cleared between enable blocks" do
    ExperimentCache.enable do
      ExperimentCache.fetch(:block) { :first_block }
      assert_equal :first_block, ExperimentCache.fetch(:block)
    end

    ExperimentCache.enable do
      assert_raises LocalJumpError do
        ExperimentCache.fetch(:block)
      end
    end
  end
end

class ExperimentCacheIntegrationTest < GitHub::IntegrationTestCase
  include Rack::Test::Methods

  setup do
    TestRoutes.draw do
      get "/experiment_cache_test", to: ->(_env) { [200, {}, [""]] }
    end
  end

  teardown do
    TestRoutes.clear!
  end

  test "is enabled and runs in an api call" do
    ExperimentCache.expects(:enable).returns([200, {}, [""]]).at_least_once

    get "/experiment_cache_test"

    assert_equal 200, last_response.status
  end
end
