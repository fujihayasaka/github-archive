# typed: true
# frozen_string_literal: true

require "test_helper"

module Search
  module Queries
    module SecurityCenter
      class QueryParserTest < GitHub::TestCase
        setup do
          @query_parser = QueryParser.new(%{
            foo:a
            bar:b
            baz:"hello world"
            aaa:
            bbb:false
            -foo:c
            unqualified-1
            props.prop_1:a_prop*value
            -bar:d:e:f
            unqualified-2
            "bar:xyz"
            props.foo-1:111,aaa,"a value:"
            props.foo#2:222,bbb,"b value:"
            unqualified_2
            -props.bar$:abc,"hello:$world"
          }.squish)
        end

        context "#parsed_query" do
          test "it returns a hash of unqualified and qualified values" do
            assert_equal(
              {
                @query_parser.send(:unqualified_key) => %w(unqualified-1 unqualified-2 "bar:xyz" unqualified_2),
                "foo" => ["a"],
                "bar" => ["b"],
                "baz" => ["hello world"],
                "aaa" => [],
                "bbb" => ["false"],
                "-foo" => ["c"],
                "props.prop_1" => ["a_prop*value"],
                "-bar" => ["d:e:f"],
                "props.foo-1" => ["111", "aaa", "a value:"],
                "props.foo#2" => ["222", "bbb", "b value:"],
                "-props.bar$" => ["abc", "hello:$world"]
              },
              @query_parser.parsed_query
            )
          end

          test "parsed_query is immutable" do
            query_parser = QueryParser.new("tool:github")
            assert_raises FrozenError do
              query_parser.get_positive_and_negative_qualified_values("tool")[0].delete("github")
            end
          end
        end

        context "#get_unqualified_values" do
          test "it returns an array of unqualified values" do
            values = @query_parser.get_unqualified_values
            assert_equal(%w(unqualified-1 unqualified-2 "bar:xyz" unqualified_2), values)
          end
        end

        context "#get_qualified_values" do
          test "it returns values when the qualifier exists" do
            values = @query_parser.get_qualified_values("-props.bar$")
            assert_equal(["abc", "hello:$world"], values)
          end

          test "returns empty array when the qualifier does not exist" do
            values = @query_parser.get_qualified_values(SecureRandom.uuid)
            assert_equal([], values)
          end
        end

        context "#get_positive_and_negative_qualified_values" do
          context "when the qualifier is positive" do
            test "it returns positive and negative values" do
              # When no negative values exist.
              positive_values, negative_values = @query_parser.get_positive_and_negative_qualified_values("baz")
              assert_equal(["hello world"], positive_values)
              assert_equal([], negative_values)

              # When negative values exist.
              positive_values, negative_values = @query_parser.get_positive_and_negative_qualified_values("foo")
              assert_equal(["a"], positive_values)
              assert_equal(["c"], negative_values)
            end
          end

          context "when the qualifier is negative" do
            test "it returns positive and negative values" do
              positive_values, negative_values = @query_parser.get_positive_and_negative_qualified_values("-foo")
              assert_equal(["a"], positive_values)
              assert_equal(["c"], negative_values)
            end
          end

          context "when qualifier has alias" do
            test "it returns values from default qualifier if it has value" do
              query_parser_with_alias = QueryParser.new(%{
                secret-scanning.test1:woof
                test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal(["woof"], positive_values)
              assert_equal([], negative_values)

              query_parser_with_alias = QueryParser.new(%{
                secret-scanning.test1:woof
                -test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal(["woof"], positive_values)
              assert_equal([], negative_values)

              query_parser_with_alias = QueryParser.new(%{
                -secret-scanning.test1:woof
                test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal([], positive_values)
              assert_equal(["woof"], negative_values)

              query_parser_with_alias = QueryParser.new(%{
                -secret-scanning.test1:woof
                -test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal([], positive_values)
              assert_equal(["woof"], negative_values)
            end

            test "it returns values from qualifier alias if default key does not exist" do
              query_parser_with_alias = QueryParser.new(%{
                test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal(["barr"], positive_values)
              assert_equal([], negative_values)

              query_parser_with_alias = QueryParser.new(%{
                -test1:barr
              }.squish)
              positive_values, negative_values = query_parser_with_alias.get_positive_and_negative_qualified_values(
                "secret-scanning.test1",
                qualifier_alias: "test1"
              )
              assert_equal([], positive_values)
              assert_equal(["barr"], negative_values)
            end
          end

          test "it returns empty arrays when a positive or negative qualifier does not exist" do
            positive_values, negative_values = @query_parser.get_positive_and_negative_qualified_values(SecureRandom.uuid)
            assert_equal([], positive_values)
            assert_equal([], negative_values)
          end
        end

        context "#custom_properties" do
          test "it returns the custom properties" do
            assert_equal(
              {
                "prop_1" => ["a_prop*value"],
                "foo-1" => ["111", "aaa", "a value:"],
                "foo#2" => ["222", "bbb", "b value:"],
                "-bar$" => ["abc", "hello:$world"]
              },
              @query_parser.custom_properties
            )
          end
        end

        context "#custom_properties_string" do
          test "it returns the custom properties string" do
            assert_equal(
              'props.prop_1:a_prop*value props.foo-1:111,aaa,"a value:" props.foo#2:222,bbb,"b value:" -props.bar$:abc,hello:$world',
              @query_parser.custom_properties_string
            )
          end
        end

        context "#to_s" do
          test "it returns a query string in the order of the original query string" do
            assert_equal(
              'foo:a bar:b baz:"hello world" aaa: bbb:false -foo:c unqualified-1 props.prop_1:a_prop*value -bar:d:e:f unqualified-2 "bar:xyz" props.foo-1:111,aaa,"a value:" props.foo#2:222,bbb,"b value:" unqualified_2 -props.bar$:abc,hello:$world',
              @query_parser.to_s
            )
          end

          context "value casing" do
            test "it downcases the values of the query string" do
              query_parser = QueryParser.new("archived:False team:My-Team -team:My-Other-Team foo:\"BAR Baz\"")
              assert_equal("archived:false team:my-team -team:my-other-team foo:\"bar baz\"", query_parser.to_s)
            end

            test "it does not downcase the values of the query string if preserve_case is true" do
              query_parser = QueryParser.new("archived:False team:My-Team -team:My-Other-Team foo:\"BAR Baz\"")
              query_parser.stubs(:preserve_case).returns(true)
              assert_equal("archived:False team:My-Team -team:My-Other-Team foo:\"BAR Baz\"", query_parser.to_s)
            end

            test "it does not downcase the values of the query string for tool" do
              query_parser = QueryParser.new("tool:GitHub -tool:\"Third Party\"")
              assert_equal("tool:GitHub -tool:\"Third Party\"", query_parser.to_s)
            end

            test "it does not downcase the values of the query string for custom properties" do
              query_parser = QueryParser.new("props.chicken:McNuggets -props.cheese:\"Burger With Bacon\"")
              assert_equal("props.chicken:McNuggets -props.cheese:\"Burger With Bacon\"", query_parser.to_s)
            end
          end
        end

        context "#reverse_negated_prefix" do
          test "it returns a query string with negation prefix reversed" do
            original = "foo:a random-string -bar:b"
            query_parser = QueryParser.new(original)
            reversed_query_parser = query_parser.reverse_negated_prefix

            assert_equal(original, query_parser.to_s)
            assert_equal("-foo:a bar:b", reversed_query_parser.to_s)
          end
        end
      end
    end
  end
end
