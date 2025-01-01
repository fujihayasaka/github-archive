# frozen_string_literal: true

require "test_helper"

class NPMIDExtractorTest < ActiveSupport::TestCase
  test "#extract_npm_id_from_reference returns nil if no reference is an NPM advisory" do
    url = generate :url
    assert_nil NPMIDExtractor.extract_npm_id_from_reference(url)
  end

  test "#extract_npm_id_from_reference returns the ID when a nodesecurity reference is present" do
    url = "https://nodesecurity.io/advisories/558"
    assert_equal 558, NPMIDExtractor.extract_npm_id_from_reference(url)
  end

  test "#extract_npm_id_from_reference returns the ID when a npm advisory reference is present" do
    url = "https://www.npmjs.com/advisories/1488"
    assert_equal 1488, NPMIDExtractor.extract_npm_id_from_reference(url)
  end

  test "#extract_npm_id_from_reference raises error if not passed a string" do
    assert_raises(ArgumentError) do
      NPMIDExtractor.extract_npm_id_from_reference(Reference.new)
    end
  end

  test "#extract_npm_id_from_reference_list returns nil if no urls are NPM URLs" do
    urls = generate_list(:url, 3)
    assert_nil NPMIDExtractor.extract_npm_id_from_reference_list(urls)
  end

  test "#extract_npm_id_from_reference_list returns ID of npm advisory reference" do
    urls = generate_list(:url, 3)
    urls << "https://nodesecurity.io/advisories/12"
    assert_equal 12, NPMIDExtractor.extract_npm_id_from_reference_list(urls)
  end

  test "#extract_npm_id_from_reference_list returns ID of first matching reference in list" do
    urls = generate_list(:url, 3)
    urls << "https://nodesecurity.io/advisories/1"
    urls << "https://www.npmjs.com/advisories/2"
    assert_equal 1, NPMIDExtractor.extract_npm_id_from_reference_list(urls)
  end

  test "#extract_npm_id_from_reference_list returns ID of node security reference" do
    urls = generate_list(:url, 3)
    urls << "https://www.npmjs.com/advisories/1122"
    assert_equal 1122, NPMIDExtractor.extract_npm_id_from_reference_list(urls)
  end

  test "#extract_npm_id_from_reference_list raises error if not passed an Arrray" do
    assert_raises(ArgumentError) do
      NPMIDExtractor.extract_npm_id_from_reference_list(generate(:url))
    end
  end
end
