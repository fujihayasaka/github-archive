# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class SearchResultSerializersTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user)
  end

  setup do
    @search_result_with_highlight = {
      "_index" => "users",
      "_type" => "user",
      "_id" => "42",
      "_score" => 7.0342846,
      "_source" =>  {
        "user_id" => 42,
        "login" => "the-dude",
        "name" => "The Dude",
        "email" => "das-dude@example.com",
        # ... and additional attributes that are not applicable to these tests
      },
      "highlight" => {
        "email" => [{ text: "das-dude@example.com", indices: [0, 8] }],
      },
      "_model" => @user,
    }
  end

  context "#text_matches" do
    test "serializes known (whitelisted) fields" do
      matches = Api::Serializer.text_matches(@search_result_with_highlight)

      assert_equal 1, matches.size
    end

    test "ignores non-whitelisted fields" do
      valid_highlight_value =
        @search_result_with_highlight["highlight"]["email"].dup

      search_result_with_unrecognized_field = @search_result_with_highlight.dup
      search_result_with_unrecognized_field["highlight"] =
        { "unrecongized-field-name" => valid_highlight_value }

      matches =
        Api::Serializer.text_matches(search_result_with_unrecognized_field)

      assert_equal 0, matches.size, matches
    end
  end

  context "blackbird_text_matches" do
    test "serializes matches" do
      result = {
        "snippets": [
          {
            "start": 10,
            "end": 45,
            "lines": ["padding foo padding", "space bar space"]
          }
        ],
        "term_matches": [
          {
            "start": 18,
            "end": 21
          },
          {
            "start": 36,
            "end": 39
          }
        ]
      }
      matches = Api::Serializer.blackbird_text_matches(result, "gopher://github.com/")
      assert_equal 1, matches.size
      assert_equal 2, matches[0][:matches].size
      assert_equal({ text: "foo", indices: [8, 11] }, matches[0][:matches][0])
      assert_equal({ text: "bar", indices: [26, 29] }, matches[0][:matches][1])
    end

    test "multiple snippets" do
      result = {
        "snippets": [
          {
            "start": 10,
            "end": 17,
            "lines": %w[foo bar]
          },
          {
            "start": 28,
            "end": 35,
            "lines": %w[baz qux]
          }
        ],
        "term_matches": [
          {
            "start": 10,
            "end": 13
          },
          {
            "start": 14,
            "end": 17
          },
          {
            "start": 28,
            "end": 31
          },
          {
            "start": 32,
            "end": 35
          }
        ]
      }
      matches = Api::Serializer.blackbird_text_matches(result, "gopher://github.com/")
      assert_equal 2, matches.size
      assert_equal 2, matches[0][:matches].size
      assert_equal({ text: "foo", indices: [0, 3] }, matches[0][:matches][0])
      assert_equal({ text: "bar", indices: [4, 7] }, matches[0][:matches][1])
      assert_equal 2, matches[1][:matches].size
      assert_equal({ text: "baz", indices: [0, 3] }, matches[1][:matches][0])
      assert_equal({ text: "qux", indices: [4, 7] }, matches[1][:matches][1])
    end

    test "match spans lines" do
      result = {
        "snippets": [
          {
            "start": 10,
            "end": 17,
            "lines": %w[foo bar]
          }
        ],
        "term_matches": [
          {
            "start": 12,
            "end": 15
          },
        ]
      }
      matches = Api::Serializer.blackbird_text_matches(result, "gopher://github.com/")
      assert_equal 1, matches.size
      assert_equal 1, matches[0][:matches].size
      assert_equal({ text: "o\nb", indices: [2, 5] }, matches[0][:matches][0])
    end

    test "invalid matches" do
      result = {
        "snippets": [
          {
            "start": 10,
            "end": 23,
            "lines": ["thisis13chars"]
          }
        ],
        "term_matches": [
          {
            "start": 8,
            "end": 15
          },
          {
            "start": 22,
            "end": 35
          }
        ]
      }
      matches = Api::Serializer.blackbird_text_matches(result, "gopher://github.com/")
      assert_equal 1, matches.size
      assert_equal 0, matches[0][:matches].size
    end

    test "invalid lines" do
      result = {
        "snippets": [
          {
            "start": 10,
            "end": 33,
            "lines": ["thisis13chars"] # actual: 10, 23
          }
        ],
        "term_matches": [
          {
            "start": 10,
            "end": 14
          },
          {
            "start": 22,
            "end": 30
          },
          {
            "start": 25,
            "end": 30
          }
        ]
      }
      matches = Api::Serializer.blackbird_text_matches(result, "gopher://github.com/")
      assert_equal 1, matches.size
      assert_equal 3, matches[0][:matches].size
      assert_equal({ text: "this", indices: [0, 4] }, matches[0][:matches][0])
      assert_equal({ text: "s", indices: [12, 20] }, matches[0][:matches][1])
      assert_equal({ text: nil, indices: [15, 20] }, matches[0][:matches][2])
    end
  end
end
