# frozen_string_literal: true

require_relative "../test_helper"

module Authnd
  module Client
    class HeadersTest < Minitest::Test
      def test_format_enabled_features_for_header
        # features must be an Array
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header(nil) }
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header("string") }
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header(123) }
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header(true) }

        # features must be an Array of Strings
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header([1, 2, 3]) }
        assert_raises(ArgumentError) { Authnd::Client.format_enabled_features_for_header(["foo", 3]) }

        assert_equal "W10=", Authnd::Client.format_enabled_features_for_header([])
        assert_equal "WyJteS1oYXBweS1mZWF0dXJlIl0=", Authnd::Client.format_enabled_features_for_header(["my-happy-feature"])
        assert_equal "WyJmZWF0dXJlMSIsImZlYXR1cmUyIiwiZmVhdHVyZTMiXQ==", Authnd::Client.format_enabled_features_for_header(%w[feature1 feature2 feature3])
      end

      def test_format_custom_header_content
        # content must be a Hash
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content("string") }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content(123) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content(true) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content([1, 2, 3]) }

        # content must have string or symbol keys and primitive values
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content({ 3 => "bad key" }) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content({ [1, 2, 3] => "bad key" }) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content({ true => "bad key" }) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content({ "bad_value" => [1, 2, 3] }) }
        assert_raises(ArgumentError) { Authnd::Client.format_custom_header_content({ "bad_value" => :symbol }) }

        assert_equal "", Authnd::Client.format_custom_header_content({})
        assert_equal "a2V5OnZhbHVlLGtleTI6MixrZXkzOnRydWU=", Authnd::Client.format_custom_header_content({ "key" => "value", :key2 => 2, "key3" => true })
      end
    end
  end
end
