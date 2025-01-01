# typed: true
# frozen_string_literal: true

require "test_helper"

class BaseLoaderTest < GitHub::TestCase
  class Klass < Issue::Loader::Base
    def load
      # do nothing
    end

    def self.load_for
      super Klass.new
    end

    def load_attribute_test
      async_preload_attribute([TestModel.new], :test_attribute, :async_test_method)
    end
  end

  class TestModel
    include PreloadableAttributes

    def async_test_method
      # do nothing
    end
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "instrumentation" do
    test "base load_for tracks execution time for instance.load" do
      Klass.load_for
      assert_equal 1, GitHub.dogstats.distributions("issue_loader.dist.time", tags: ["fn:klass:load_for"]).length
      assert span = find_span_by(name: "issue_loader::klass::load_for")
      assert_same_hash({ "mysql_queries" => 0 }, span.attributes)
    end

    test "base async_preload_attribute tracks execution time" do
      Klass.new.load_attribute_test
      assert_equal 1, GitHub.dogstats.distributions("async_preload_attribute.dist.time", tags: [
        "class:klass", "method:load_attribute_test", "attribute:test_attribute.async_test_method", "model_count:1-10"]).length
    end
  end
end
