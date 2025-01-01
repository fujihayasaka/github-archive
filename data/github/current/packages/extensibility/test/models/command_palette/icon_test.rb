# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class IconTest < GitHub::TestCase
    test "has a type" do
      icon = Icon.new(type: :some_type)
      refute_nil icon.type
    end

    test "responds to #as_json" do
      icon = Icon.new(type: :some_type)
      assert icon.respond_to?(:as_json)
    end

    test "raises when #as_json is invoked" do
      icon = Icon.new(type: :some_type)
      assert_raises NotImplementedError do
        icon.as_json
      end
    end
  end
end
