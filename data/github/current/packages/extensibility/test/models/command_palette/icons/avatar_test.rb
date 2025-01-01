# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Icons
    class IconsAvatarTest < GitHub::TestCase
      fixtures do
        @url = "https://github.com/monalisa.png"
      end

      test "has a type" do
        icon = Avatar.new(url: @url, alt: "@monalisa")
        assert_equal :avatar, icon.type
      end

      test "has a url" do
        icon = Avatar.new(url: @url, alt: "@monalisa")
        assert icon.url.is_a?(String)
        assert icon.url =~ URI.regexp
      end

      test "doesn't raise when #as_json is invoked" do
        icon = Avatar.new(url: @url, alt: "@monalisa")
        assert icon.as_json.is_a?(Hash)
      end
    end
  end
end
