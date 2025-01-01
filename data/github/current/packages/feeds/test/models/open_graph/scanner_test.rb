# typed: true
# frozen_string_literal: true

require "test_helper"

class OpenGraph::ScannerTest < GitHub::TestCase
  test "scans a page for open graph data" do
    VCR.use_cassette("open_graph_scanner.success") do
      scanner = OpenGraph::Scanner.new("https://github.com/facebook/react")
      result = scanner.scan

      assert_includes result.title, "facebook/react"
      assert_includes result.description, "JavaScript library"
      assert_equal result.image_width, "1200"
      assert_equal result.image_height, "600"
    end
  end

  context "#ok?" do
    test "returns true when the status is 200" do
      VCR.use_cassette("open_graph_scanner.success") do
        scanner = OpenGraph::Scanner.new("https://github.com/facebook/react")
        result = scanner.scan
        assert_predicate result, :ok?
      end
    end

    context "external urls" do
      test "does not make a request for http" do
        VCR.use_cassette("open_graph_scanner.external.success") do
          GitHub::FaradayClient::External.any_instance.expects(:get).never
          scanner = OpenGraph::Scanner.new("http://youtube.com")
          result = scanner.scan
          assert_predicate result, :empty?
          refute_predicate result, :ok?
        end
      end
    end

    test "returns false when the status is not 200" do
      VCR.use_cassette("open_graph_scanner.not_found") do
        scanner = OpenGraph::Scanner.new("https://github.com/404")
        result = scanner.scan
        refute_predicate result, :ok?
      end
    end
  end

  test "returns an error when the request fails" do
    VCR.use_cassette("open_graph_scanner.error") do
      scanner = OpenGraph::Scanner.new("https://lolnowaythisisreal.yeahitsdefinitelyfake")
      result = scanner.scan
      refute_predicate result, :success?
    end
  end
end
