# typed: true
# frozen_string_literal: true

require "test_helper"

class FundingLinksBlobParserTest < GitHub::TestCase
  context ".load" do
    test "with valid yaml" do
      blob = "patreon: github"
      parsed = FundingLinks::BlobParser.load(blob: blob)
      refute_empty parsed
      assert parsed["patreon"], "Expected white-listed key, got nil"
    end

    test "with invalid yaml" do
      blob = ":patreon: github"
      parsed = FundingLinks::BlobParser.load(blob: blob)
      assert_nil parsed
    end
  end
end
