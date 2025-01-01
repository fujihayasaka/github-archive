# typed: true
# frozen_string_literal: true

require "test_helper"

class PreloadableAttributesTest < GitHub::TestCase
  class NoPreloadables
    include PreloadableAttributes
  end

  class AttributePreloadable
    include PreloadableAttributes
    attr_preloadable :foo, :bar
    attr_reader :foo, :bar
  end

  context "preload_attr" do
    test "raises if no preloadables defined" do
      it = NoPreloadables.new
      err = assert_raises do
        it.preload_attr(:foo, "bar")
      end

      assert_equal "No preloadables defined for PreloadableAttributesTest::NoPreloadables", err.message
    end

    test "raises if attribute is not preloadable" do
      it = AttributePreloadable.new
      err = assert_raises do
        it.preload_attr(:baz, "raz")
      end

      assert_equal "Attribute baz not defined as preloadable for PreloadableAttributesTest::AttributePreloadable", err.message
    end

    test "must not raise if attribute is a preloadable" do
      it = AttributePreloadable.new

      it.preload_attr(:foo, "bar")

      assert_equal "bar", it.foo
    end

    test "raises if the preloadable is already set" do
      it = AttributePreloadable.new
      it.preload_attr(:foo, "bar")

      err = assert_raises do
        it.preload_attr(:foo, "baz")
      end

      assert_equal "Preloadable foo already set", err.message
    end
  end
end
