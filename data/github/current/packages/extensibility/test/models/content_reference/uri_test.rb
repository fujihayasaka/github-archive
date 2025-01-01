# typed: true
# frozen_string_literal: true

require "test_helper"

class ContentReferenceUriTest < GitHub::TestCase
  test "returns host" do
    assert_equal "runkit.com", ContentReference::Uri.host("https://runkit.com/some/notebook#page2")
  end
end
