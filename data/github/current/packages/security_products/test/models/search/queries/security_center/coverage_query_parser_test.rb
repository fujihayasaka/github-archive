# typed: true
# frozen_string_literal: true

require "test_helper"

module Search
  module Queries
    module SecurityCenter
      class CoverageQueryParserTest < GitHub::TestCase

        STATUS_QUALIFIERS = [
          :"code-scanning-alerts",
          :"code-scanning-pull-request-alerts",
          :"code-scanning-default-setup",
          :"dependabot-alerts",
          :"dependabot-security-updates",
          :"secret-scanning-alerts",
          :"secret-scanning-push-protection",
        ].freeze

        context "#values_for_qualifier" do
          test "it returns the value for the given qualifier" do
            pos, neg = CoverageQueryParser.new("is:something").values_for_qualifier(:is)
            assert_equal ["something"], pos
            assert_empty neg

            pos, neg = CoverageQueryParser.new("archived:whatever is:something some text").values_for_qualifier(:is)
            assert_equal ["something"], pos
            assert_empty neg
          end

          test "it returns the negated value for the given qualifier" do
            pos, neg = CoverageQueryParser.new("-is:something").values_for_qualifier(:is)
            assert_empty pos
            assert_equal ["something"], neg

            pos, neg = CoverageQueryParser.new("-archived:whatever -is:something NOT some text").values_for_qualifier(:is)
            assert_empty pos
            assert_equal ["something"], neg
          end

          test "it returns empty arrays when no values are specified for the given qualifier" do
            pos, neg = CoverageQueryParser.new("").values_for_qualifier(:is)
            assert_empty pos
            assert_empty neg

            pos, neg = CoverageQueryParser.new("archived:whatever").values_for_qualifier(:is)
            assert_empty pos
            assert_empty neg
          end

          test "it returns empty arrays for unsupported qualifiers" do
            pos, neg = CoverageQueryParser.new("").values_for_qualifier(:unsupported)
            assert_empty pos
            assert_empty neg

            pos, neg = CoverageQueryParser.new("is:something unsupported:happening").values_for_qualifier(:unsupported)
            assert_empty pos
            assert_empty neg
          end

          test "it returns all values for the given qualifier" do
            pos, neg = CoverageQueryParser.new("is:something,cool -is:going,on").values_for_qualifier(:is)
            assert_same_elements %w[something cool], pos
            assert_same_elements %w[going on], neg
          end
        end

        context "#values_without_qualifiers" do
          test "it returns the unqualified value" do
            pos, neg = CoverageQueryParser.new("something").values_without_qualifiers
            assert_equal ["something"], pos
            assert_empty neg
          end

          test "it returns the unqualified negated value" do
            pos, neg = CoverageQueryParser.new("NOT something").values_without_qualifiers
            assert_empty pos
            assert_equal ["something"], neg
          end

          test "it returns empty arrays when there are no unqualified values" do
            pos, neg = CoverageQueryParser.new("").values_without_qualifiers
            assert_empty pos
            assert_empty neg

            pos, neg = CoverageQueryParser.new("is:something").values_without_qualifiers
            assert_empty pos
            assert_empty neg
          end

          test "it returns all unqualified values" do
            pos, neg = CoverageQueryParser.new("one,two is:three NOT four,five").values_without_qualifiers
            assert_same_elements %w[one two], pos
            assert_same_elements %w[four five], neg
          end
        end

        context "#sort_by" do
          test "it returns nil field and direction if no sort is specified" do
            field, dir = CoverageQueryParser.new("").sort_by
            assert_nil field
            assert_nil dir

            field, dir = CoverageQueryParser.new("is:something").sort_by
            assert_nil field
            assert_nil dir
          end

          test "it returns value with nil direction when no recognized direction suffix is provided" do
            field, dir = CoverageQueryParser.new("sort:my-field").sort_by
            assert_equal "my-field", field
            assert_nil dir
          end

          test "it splits and returns the field and direction values" do
            field, dir = CoverageQueryParser.new("sort:my-field-asc").sort_by
            assert_equal "my-field", field
            assert_equal "asc", dir

            field, dir = CoverageQueryParser.new("sort:my-field-desc").sort_by
            assert_equal "my-field", field
            assert_equal "desc", dir
          end
        end

        context "#has_filter_by_status?" do
          test "returns false when unfiltered" do
            refute CoverageQueryParser.new("").has_filter_by_status?
          end

          STATUS_QUALIFIERS.each do |qualifier|
            test "returns true when filtered by #{qualifier}" do
              assert CoverageQueryParser.new("#{qualifier}:10").has_filter_by_status?
              assert CoverageQueryParser.new("#{qualifier}:>0").has_filter_by_status?
              assert CoverageQueryParser.new("#{qualifier}:enabled").has_filter_by_status?
              assert CoverageQueryParser.new("#{qualifier}:not-enabled").has_filter_by_status?
              assert CoverageQueryParser.new("-#{qualifier}:10").has_filter_by_status?
              assert CoverageQueryParser.new("-#{qualifier}:>0").has_filter_by_status?
              assert CoverageQueryParser.new("-#{qualifier}:enabled").has_filter_by_status?
              assert CoverageQueryParser.new("-#{qualifier}:not-enabled").has_filter_by_status?
            end
          end

          (CoverageQueryParser::QUALIFIERS - STATUS_QUALIFIERS).each do |qualifier|
            test "returns false when filtered by '#{qualifier}'" do
              refute CoverageQueryParser.new("#{qualifier}:foobar").has_filter_by_status?
            end
          end
        end
      end
    end
  end
end
