# typed: true
# frozen_string_literal: true

require "test_helper"

class FundingLinksFileParserTest < GitHub::TestCase
  context ".load" do
    context "when repo has a funding file" do
      test "is not empty when valid" do
        repo = create :repository, from_example: :funding_links

        parsed = FundingLinks::FileParser.load(
          repo,
          path: FundingLinks::FILENAME,
          directory: FundingLinks::DIRECTORY,
        )
        refute_empty parsed
      end

      test "is case-insensitive" do
        repo = create :repository, from_example: :funding_links

        parsed = FundingLinks::FileParser.load(
          repo,
          path: FundingLinks::FILENAME.downcase,
          directory: FundingLinks::DIRECTORY,
        )
        refute_empty parsed
      end

      test "is nil when invalid" do
        repo = create :repository, from_example: :invalid_funding_links

        parsed = FundingLinks::FileParser.load(
          repo,
          path: FundingLinks::FILENAME,
          directory: FundingLinks::DIRECTORY,
        )
        assert_nil parsed
      end
    end

    context "when repo has no funding file" do
      test "is nil" do
        repo = create :repository
        assert_nil FundingLinks::FileParser.load(
          repo,
          path: FundingLinks::FILENAME,
          directory: FundingLinks::DIRECTORY,
        )
      end
    end
  end
end
