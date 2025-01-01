# typed: true
# frozen_string_literal: true

require "test_helper"

class AlloyManifestTest < GitHub::TestCase
  include Alloy::StubHelper

  test "returns the manifest filename" do
    with_stubbed_manifest do
      assert_equal Alloy::Manifest.filename, "manifest-deadbeef.json"
    end
  end

  test "gets supported entry points from manifest" do
    with_stubbed_manifest do
      assert_equal Alloy::Manifest.entry_supports_ssr?("invalid"), false
      assert_equal Alloy::Manifest.entry_supports_ssr?("react-sandbox"), true
    end
  end

  test "returns true if there are no ssrNames" do
    with_stubbed_manifest(Rails.root.join("test/fixtures/alloy/manifest.no-ssrNames.json")) do
      assert_equal Alloy::Manifest.entry_supports_ssr?("invalid"), true
    end
  end
end
