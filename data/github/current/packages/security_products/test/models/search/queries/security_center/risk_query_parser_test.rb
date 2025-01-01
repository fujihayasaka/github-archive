# typed: true
# frozen_string_literal: true

require "test_helper"

module Search
  module Queries
    module SecurityCenter
      class RiskQueryParserTest < GitHub::TestCase

        STATUS_QUALIFIERS = [
          :"code-scanning-alerts",
          :"dependabot-alerts",
          :"secret-scanning-alerts",
        ].freeze

        context "#values_for_qualifier" do
          test "it returns the value for the given qualifier" do
            pos, neg = RiskQueryParser.new("is:something").values_for_qualifier(:is)
            assert_equal ["something"], pos
            assert_empty neg

            pos, neg = RiskQueryParser.new("archived:whatever is:something some text").values_for_qualifier(:is)
            assert_equal ["something"], pos
            assert_empty neg
          end

          test "it returns the negated value for the given qualifier" do
            pos, neg = RiskQueryParser.new("-is:something").values_for_qualifier(:is)
            assert_empty pos
            assert_equal ["something"], neg

            pos, neg = RiskQueryParser.new("-archived:whatever -is:something NOT some text").values_for_qualifier(:is)
            assert_empty pos
            assert_equal ["something"], neg
          end

          test "it returns empty arrays when no values are specified for the given qualifier" do
            pos, neg = RiskQueryParser.new("").values_for_qualifier(:is)
            assert_empty pos
            assert_empty neg

            pos, neg = RiskQueryParser.new("archived:whatever").values_for_qualifier(:is)
            assert_empty pos
            assert_empty neg
          end

          test "it returns empty arrays for unsupported qualifiers" do
            pos, neg = RiskQueryParser.new("").values_for_qualifier(:unsupported)
            assert_empty pos
            assert_empty neg

            pos, neg = RiskQueryParser.new("is:something unsupported:happening").values_for_qualifier(:unsupported)
            assert_empty pos
            assert_empty neg
          end

          test "it returns all values for the given qualifier" do
            pos, neg = RiskQueryParser.new("is:something,cool -is:going,on").values_for_qualifier(:is)
            assert_same_elements %w[something cool], pos
            assert_same_elements %w[going on], neg
          end
        end

        context "#values_without_qualifiers" do
          test "it returns the unqualified value" do
            pos, neg = RiskQueryParser.new("something").values_without_qualifiers
            assert_equal ["something"], pos
            assert_empty neg
          end

          test "it returns the unqualified negated value" do
            pos, neg = RiskQueryParser.new("NOT something").values_without_qualifiers
            assert_empty pos
            assert_equal ["something"], neg
          end

          test "it returns empty arrays when there are no unqualified values" do
            pos, neg = RiskQueryParser.new("").values_without_qualifiers
            assert_empty pos
            assert_empty neg

            pos, neg = RiskQueryParser.new("is:something").values_without_qualifiers
            assert_empty pos
            assert_empty neg
          end

          test "it returns all unqualified values" do
            pos, neg = RiskQueryParser.new("one,two is:three NOT four,five").values_without_qualifiers
            assert_same_elements %w[one two], pos
            assert_same_elements %w[four five], neg
          end
        end

        context "#sort_by" do
          test "it returns nil field and direction if no sort is specified" do
            field, dir = RiskQueryParser.new("").sort_by
            assert_nil field
            assert_nil dir

            field, dir = RiskQueryParser.new("is:something").sort_by
            assert_nil field
            assert_nil dir
          end

          test "it returns value with nil direction when no recognized direction suffix is provided" do
            field, dir = RiskQueryParser.new("sort:my-field").sort_by
            assert_equal "my-field", field
            assert_nil dir
          end

          test "it splits and returns the field and direction values" do
            field, dir = RiskQueryParser.new("sort:my-field-asc").sort_by
            assert_equal "my-field", field
            assert_equal "asc", dir

            field, dir = RiskQueryParser.new("sort:my-field-desc").sort_by
            assert_equal "my-field", field
            assert_equal "desc", dir
          end
        end

        context "#has_filter_by_status?" do
          test "returns false when unfiltered" do
            refute RiskQueryParser.new("").has_filter_by_status?
          end

          STATUS_QUALIFIERS.each do |qualifier|
            test "returns true when filtered by #{qualifier}" do
              assert RiskQueryParser.new("#{qualifier}:10").has_filter_by_status?
              assert RiskQueryParser.new("#{qualifier}:>0").has_filter_by_status?
              assert RiskQueryParser.new("#{qualifier}:enabled").has_filter_by_status?
              assert RiskQueryParser.new("#{qualifier}:not-enabled").has_filter_by_status?
              assert RiskQueryParser.new("-#{qualifier}:10").has_filter_by_status?
              assert RiskQueryParser.new("-#{qualifier}:>0").has_filter_by_status?
              assert RiskQueryParser.new("-#{qualifier}:enabled").has_filter_by_status?
              assert RiskQueryParser.new("-#{qualifier}:not-enabled").has_filter_by_status?
            end
          end

          (RiskQueryParser::QUALIFIERS - STATUS_QUALIFIERS).each do |qualifier|
            test "returns false when filtered by '#{qualifier}'" do
              refute RiskQueryParser.new("#{qualifier}:foobar").has_filter_by_status?
            end
          end
        end

        context "#has_filter_by_severity?" do
          test "returns false when unfiltered" do
            refute RiskQueryParser.new("").has_filter_by_severity?
          end

          test "returns true when filtered by 'has-severity'" do
            assert RiskQueryParser.new("has-severity:high").has_filter_by_severity?
            assert RiskQueryParser.new("has-severity:medium").has_filter_by_severity?
            assert RiskQueryParser.new("has-severity:low").has_filter_by_severity?
            assert RiskQueryParser.new("has-severity:foo").has_filter_by_severity?
          end

          (RiskQueryParser::QUALIFIERS - [:"has-severity"]).each do |qualifier|
            test "returns false when filtered by '#{qualifier}'" do
              refute RiskQueryParser.new("#{qualifier}:foobar").has_filter_by_severity?
            end
          end
        end
      end
    end
  end
end
