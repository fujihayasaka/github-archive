# typed: true
# frozen_string_literal: true

require "test_helper"

class ReposNoFilterTest < GitHub::TestCase
  setup do
    @regex_text = "props\\.\\w+"
    @terms = [@regex_text]
  end

  context "#build" do
    test "returns empty list if no: qualifier is not present" do
      filter = build_filter
      expected = []

      assert_equal expected, filter.build(["version:none", "secure:true"])
    end

    test "ignores values not matching pattern" do
      filter = build_filter
      expected = [
        { prefix: { sample: "env:" } }
      ]

      assert_equal expected, filter.build(["no:props.env", "no:unknown"])
    end

    context "custom properties" do
      test "converts no: into a prefix filter" do
        filter = build_filter
        expected = [
          { prefix: { sample: "env:" } }
        ]

        assert_equal expected, filter.build(["no:props.env", "version:none", "secure:true"])
      end
    end
  end

  def build_filter(query_text = "")
    parsed_query = Search::ParsedQuery.new(query_text, @terms, nil, @terms)
    opts = {
      field: :sample,
      key_regex: /#{@regex_text}/,
      qualifiers: parsed_query.qualifiers,
    }
    Search::Filters::ReposNoFilter.new(opts)
  end
end
