# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityCenterBaseTest < GitHub::TestCase
  fixtures do
    @query_parser_no_implementation = Class.new(Search::Queries::SecurityCenter::Base)

    @query_parser = Class.new(Search::Queries::SecurityCenter::Base) do
      class << self
        protected

        def allowed_qualifiers
          [:provider, :"secret-type", :sort]
        end
      end
    end
  end

  context "required methods are not implemented" do
    test "it raises an error" do
      assert_raises(NotImplementedError) do
        @query_parser_no_implementation.add_or_remove("", "foo", "bar")
      end
    end
  end

  context ".parse" do
    test "negated qualifiers are correctly parsed" do
      parsed_query = @query_parser.parse("-sort:severity -provider:foo,bar provider:baz -gibberish secret-type:foo,\"woof woof\"")

      expected_value = {
        "_literals" => ["-gibberish"],
        "-sort" => ["severity"],
        "-provider" => %w[foo bar],
        "provider" => ["baz"],
        "secret-type" => ["foo", "woof woof"]
      }
      assert_equal expected_value, parsed_query
    end

    test "parses values with inner commas 1" do
      parsed_query = @query_parser.parse("secret-type:foo,\"woof, woof\",\"bar\"")

      expected_value = {
        "_literals" => [],
        "secret-type" => ["foo", "woof, woof", "bar"]
      }
      assert_equal expected_value, parsed_query
    end

    test "parses values with inner commas 2" do
      parsed_query = @query_parser.parse("secret-type:\"woof, woof\"")

      expected_value = {
        "_literals" => [],
        "secret-type" => ["woof, woof"]
      }
      assert_equal expected_value, parsed_query
    end

    test "parses compound query" do
      parsed_query = @query_parser.parse("secret-type:\"woof, woof\" provider:baz,\"bar\"")

      expected_value = {
        "_literals" => [],
        "provider" => %w(baz bar),
        "secret-type" => ["woof, woof"]
      }
      assert_equal expected_value, parsed_query
    end
  end

  context ".canonicalize" do
    test "sorts the query string" do
      query_string = @query_parser.canonicalize("b secret-type:slug_2 secret-type:slug_3,slug_1 c provider:foo,bar a")
      assert_equal "a,b,c provider:bar,foo secret-type:slug_1,slug_2,slug_3", query_string
    end

    test "sorts negated qualifiers" do
      query_string = @query_parser.canonicalize("secret-type:slug_1 -secret-type:slug_2")
      assert_equal "-secret-type:slug_2 secret-type:slug_1", query_string
    end

    test "ignores extra whitespace" do
      query_string = @query_parser.canonicalize("   b    secret-type:slug_2,slug_1   c   provider:foo,bar   a   ")
      assert_equal "a,b,c provider:bar,foo secret-type:slug_1,slug_2", query_string
    end
  end

  context ".add_or_remove" do
    test "adding" do
      query_string = @query_parser.add_or_remove("secret-type:slug_1", :"secret-type", "slug_2")
      assert_equal "secret-type:slug_1,slug_2", query_string
    end

    test "adding value with spaces" do
      query_string = @query_parser.add_or_remove("secret-type:slug_1", :"secret-type", "slug_2 space")
      assert_equal "secret-type:slug_1,\"slug_2 space\"", query_string
    end

    test "removing" do
      query_string = @query_parser.add_or_remove("secret-type:slug_1", :"secret-type", "slug_1")
      assert_equal "", query_string
    end

    test "removing value with spaces" do
      query_string = @query_parser.add_or_remove("secret-type:\"slug_1 space\"", :"secret-type", "slug_1 space")
      assert_equal "", query_string
    end

    test "unqualified text remains in the query" do
      query_string = @query_parser.add_or_remove("hello world secret-type:slug_1", :"secret-type", "slug_2")
      assert_equal "hello world secret-type:slug_1,slug_2", query_string
    end
  end

  context ".add_or_replace" do
    test "adding" do
      query_string = @query_parser.add_or_replace("", :"secret-type", "slug_1")
      assert_equal "secret-type:slug_1", query_string
    end

    test "adding value with spaces" do
      query_string = @query_parser.add_or_replace("", :"secret-type", "slug_1 space")
      assert_equal "secret-type:\"slug_1 space\"", query_string
    end

    test "replacing" do
      query_string = @query_parser.add_or_replace("secret-type:slug_1", :"secret-type", "slug_2")
      assert_equal "secret-type:slug_2", query_string
    end

    test "replacing value with spaces" do
      query_string = @query_parser.add_or_replace("secret-type:slug_1", :"secret-type", "slug_1 space")
      assert_equal "secret-type:\"slug_1 space\"", query_string
    end

    test "value with comma is treated as a single value" do
      query_string = @query_parser.add_or_replace("secret-type:slug_1", :"secret-type", "slug_1,space")
      assert_equal "secret-type:\"slug_1,space\"", query_string
    end

    test "supports multiple values by passing in an array" do
      query_string = @query_parser.add_or_replace("secret-type:slug_1", :"secret-type", ["slug_1,space", "slug2"])
      assert_equal "secret-type:\"slug_1,space\",slug2", query_string
    end

    test "unqualified text remains in the query" do
      query_string = @query_parser.add_or_replace("hello world secret-type:slug_1", :"secret-type", "slug_2")
      assert_equal "hello world secret-type:slug_2", query_string
    end
  end

  context ".any_qualifiers_exist?" do
    test "returns false if none of the qualifiers are in the query" do
      refute @query_parser.any_qualifiers_exist?("", [:"secret-type", :provider])
    end

    test "returns true if at least 1 qualifier is in the query" do
      assert @query_parser.any_qualifiers_exist?("secret-type:high", [:"secret-type", :provider, :sort])
      assert @query_parser.any_qualifiers_exist?("provider:foo secret-type:slug_1", [:"secret-type", :provider, :sort])
    end
  end

  context ".remove_qualifier" do
    test "removing" do
      query_string = @query_parser.remove_qualifier("secret-type:slug_1", :"secret-type")
      assert_equal "", query_string
    end

    test "unqualified text remains in the query" do
      query_string = @query_parser.remove_qualifier("hello world secret-type:slug_1", :"secret-type")
      assert_equal "hello world", query_string
    end
  end

  context ".query_string_for_url" do
    test 'returns "?" if blank query' do
      query_url = @query_parser.query_string_for_url("")
      assert_equal "?", query_url
    end

    test "returns URL query string when query is not blank" do
      query_url = @query_parser.query_string_for_url("hello world secret-type:slug_1 provider:foo")
      assert_equal "?query=hello+world+secret-type%3Aslug_1+provider%3Afoo", query_url
    end

    test "returns URL query string when query value contains spaces" do
      query_url = @query_parser.query_string_for_url("hello world secret-type:\"slug_1 space\" provider:foo")
      assert_equal "?query=hello+world+secret-type%3A%22slug_1+space%22+provider%3Afoo", query_url
    end

    test "returns URL query string when query has negation" do
      query_url = @query_parser.query_string_for_url("-severity:high")
      assert_equal "?query=-severity%3Ahigh", query_url
    end
  end

  context ".get_qualified_values" do
    test "returns values when query present" do
      values = @query_parser.get_qualified_values("hello world secret-type:slug_1,slug_2 provider:foo", :"secret-type")
      assert_equal %w[slug_1 slug_2], values
    end

    test "returns value that contains spaces" do
      values = @query_parser.get_qualified_values("hello world secret-type:\"slug_1 space\" provider:foo", :"secret-type")
      assert_equal ["slug_1 space"], values
    end

    test "returns empty array when blank query" do
      values = @query_parser.get_qualified_values("", :"secret-type")
      assert_equal [], values
    end

    test "returns empty array when qualifier not in query" do
      values = @query_parser.get_qualified_values("provider:foo", :"secret-type")
      assert_equal [], values
    end

    test "ignores unqualified text" do
      values = @query_parser.get_qualified_values("hello world", :"secret-type")
      assert_equal [], values
    end
  end

  context ".get_unqualified_values" do
    test "returns an array of unqualified values" do
      unqualified_values = @query_parser.get_unqualified_values("hello world secret-type:slug_1 provider:foo")
      assert_equal %w[hello world], unqualified_values
    end
  end

  context ".has_duplicate_qualifiers?" do
    test "returns false when query is blank" do
      refute @query_parser.has_duplicate_qualifiers?("")
    end

    test "returns false when no duplicate qualifiers" do
      refute @query_parser.has_duplicate_qualifiers?("secret-type:slug_1 provider:foo")
    end

    test "returns true when duplicate qualifiers" do
      assert @query_parser.has_duplicate_qualifiers?("secret-type:slug_1 secret-type:slug_2 provider:foo")
    end

    test "ignores unqualified text" do
      refute @query_parser.has_duplicate_qualifiers?("hello hello")
    end
  end

  context ".has_conflicting_values?" do
    test "returns false when query is blank" do
      refute @query_parser.has_conflicting_values?("")
    end

    test "returns false when no conflicting values" do
      refute @query_parser.has_conflicting_values?("-secret-type:slug_1 secret-type:slug_2")
      refute @query_parser.has_conflicting_values?("-secret-type:slug_1 secret-type:slug_1,slug_2") # has unshared values in the positive qualifier
      refute @query_parser.has_conflicting_values?("-secret-type:slug_1,slug_2 secret-type:slug_1,slug_3") # has unshared values in both qualifiers
      refute @query_parser.has_conflicting_values?("-secret-type: secret-type:") # no values
    end

    test "returns true when conflicting values" do
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1 secret-type:slug_1")
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1,slug_2 secret-type:slug_1") # has unshared values in the negative qualifier
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1,slug_1 secret-type:slug_1") # duplication in the negative qualifier
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1 secret-type:slug_1,slug_1") # duplication in the positive qualifier
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1,slug_2 secret-type:slug_1,slug_2") # multiple values in same order
      assert @query_parser.has_conflicting_values?("-secret-type:slug_2,slug_1 secret-type:slug_1,slug_2") # multiple values with different order
      assert @query_parser.has_conflicting_values?("-secret-type:slug_1,slug_2 secret-type:SLUG_1,SLUG_2") # multiple values with different casing
    end

    test "ignores unqualified text" do
      refute @query_parser.has_conflicting_values?("hello hello")
    end
  end

  context ".has_qualifiers_without_value?" do
    test "returns false when query is blank" do
      refute @query_parser.has_qualifiers_without_value?
      refute @query_parser.has_qualifiers_without_value?(nil)
      refute @query_parser.has_qualifiers_without_value?("")
    end

    test "returns false when no qualifiers used" do
      refute @query_parser.has_qualifiers_without_value?("foo")
      refute @query_parser.has_qualifiers_without_value?("foo bar")
    end

    test "returns false when all qualifiers have values" do
      refute @query_parser.has_qualifiers_without_value?("provider:foo")
      refute @query_parser.has_qualifiers_without_value?("provider:foo bar")
      refute @query_parser.has_qualifiers_without_value?("provider:foo secret-type:bar")
      refute @query_parser.has_qualifiers_without_value?("provider:foo secret-type:bar baz")
    end

    test "returns true when qualifier used without value" do
      assert @query_parser.has_qualifiers_without_value?("provider:")
      assert @query_parser.has_qualifiers_without_value?("provider: foo")
      assert @query_parser.has_qualifiers_without_value?("provider: secret-type:foo")
      assert @query_parser.has_qualifiers_without_value?("provider: secret-type:foo bar")
    end
  end

  context ".is_valid?" do
    test "returns true when query is blank" do
      assert @query_parser.is_valid?("")
    end

    test "returns false when no value" do
      refute @query_parser.is_valid?("secret-type:")
    end

    test "returns false if qualifier not valid" do
      refute @query_parser.is_valid?("bad-qualifier:slug_1")
    end

    test "returns false if duplicate qualifiers" do
      refute @query_parser.is_valid?("secret-type:slug_1 secret-type:slug_2")
    end

    test "returns false if conflicting values" do
      refute @query_parser.is_valid?("-secret-type:slug_1 secret-type:slug_1")
    end

    test "returns true for a correct query" do
      assert @query_parser.is_valid?("secret-type:slug_1,slug_2 provider:foo")
    end

    test "returns true when value contains spaces" do
      assert @query_parser.is_valid?("secret-type:\"slug_1 space\"")
    end

    test "returns true when value contains separator" do
      assert @query_parser.is_valid?("secret-type:slug_1:slug_2")
    end

    test "returns true for unqualified values" do
      assert @query_parser.is_valid?("hello world")
    end
  end

  context ".pair_exists?" do
    test "returns false if qualifier not in query" do
      refute @query_parser.pair_exists?("secret-type:slug_1", :provider, "prov_1")
    end

    test "returns false if qualifier does not have value" do
      refute @query_parser.pair_exists?("secret-type:slug_1", :"secret-type", "slug_2")
    end

    test "returns true if qualifier with value exist" do
      assert @query_parser.pair_exists?("secret-type:slug_1", :"secret-type", "slug_1")
    end

    test "returns true if qualifier with value exist when value contains spaces" do
      assert @query_parser.pair_exists?("secret-type:\"slug_1 space\"", :"secret-type", "slug_1 space")
    end
  end

  context ".qualifier_exists?" do
    test "returns false if qualifier is not in query" do
      refute @query_parser.qualifier_exists?("secret-type:slug_1", :provider)
    end

    test "returns true if qualifier is in query" do
      assert @query_parser.qualifier_exists?("secret-type:slug_1", :"secret-type")
    end
  end

  context ".toggle_qualifier" do
    test "adds qualifier if it does not exist" do
      assert_equal "provider:github", @query_parser.toggle_qualifier("", :provider, "github")
      assert_equal "sort:foo provider:github", @query_parser.toggle_qualifier("sort:foo", :provider, "github")
    end

    test "removes qualifier if it exists" do
      assert_equal "", @query_parser.toggle_qualifier("provider:github", :provider, "github")
      assert_equal "sort:foo", @query_parser.toggle_qualifier("provider:github sort:foo", :provider, "github")
      assert_equal "", @query_parser.toggle_qualifier("provider:github,slack", :provider, "github")
    end

    test "replaces qualifier if it exists with another value" do
      assert_equal "provider:github", @query_parser.toggle_qualifier("provider:slack", :provider, "github")
      assert_equal "provider:github sort:foo", @query_parser.toggle_qualifier("provider:slack sort:foo", :provider, "github")
    end
  end
end
