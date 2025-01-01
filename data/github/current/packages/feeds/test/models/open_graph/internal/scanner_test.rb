# typed: true
# frozen_string_literal: true

require "test_helper"

class OpenGraph::Internal::ScannerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "external url returns empty result when using internal scanner" do
    VCR.use_cassette("open_graph_scanner.internal.external") do
      scanner = OpenGraph::Internal::Scanner.new("https://www.youtube.com/watch?v=pBy1zgt0XPc")
      result = scanner.scan

      assert_predicate result, :empty?
    end
  end

  test "internal url" do
    VCR.use_cassette("open_graph_scanner.internal.internal") do
      scanner = OpenGraph::Internal::Scanner.new("https://github.com/facebook/react")
      result = scanner.scan

      assert_includes result.title, "facebook/react"
      assert_includes result.description, "JavaScript library"
      assert_includes result.image, "camo"
      assert_equal result.image_width, "1200"
      assert_equal result.image_height, "600"
    end
  end
end
