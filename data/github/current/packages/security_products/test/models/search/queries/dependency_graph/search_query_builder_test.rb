# typed: true
# frozen_string_literal: true

require "test_helper"

module Search
  module Queries
    module DependencyGraph
      class SearchQueryBuilderTest < ActiveSupport::TestCase
        def setup
          @builder = SearchQueryBuilder
        end

        test "should return the raw query" do
          query = "express relationship:direct ecosystem:npm"
          query_builder = @builder.new(query: query)
          assert_equal query, query_builder.raw_query
        end

        test "should return the search query" do
          query = "some_query relationship:direct"
          query_builder = @builder.new(query: query)
          assert_equal "some_query", query_builder.search_query
        end

        test "should return multiple search queries" do
          query = "react express relationship:direct"
          query_builder = @builder.new(query: query)
          assert_equal "react express", query_builder.search_query
        end

        test "should handle nil query gracefully" do
          query = nil
          query_builder = @builder.new(query: query)
          assert_nil query_builder.raw_query
        end

        test "should handle empty query gracefully" do
          query = ""
          query_builder = @builder.new(query: query)
          assert_equal "", query_builder.raw_query
        end

        test "should retain only the last relationship filter in query" do
          query = "some_query relationship:direct relationship:transitive"
          query_builder = @builder.new(query: query)
          assert_equal "some_query relationship:transitive", query_builder.raw_query
          assert_equal "transitive", query_builder.relationship
        end

        test "should retain only the last ecosystem filter in query" do
          query = "some_query ecosystem:RubyGems ecosystem:npm"
          query_builder = @builder.new(query: query)
          assert_equal "some_query ecosystem:npm", query_builder.raw_query
          assert_equal "npm", query_builder.ecosystem
        end

        test "should validate multiple filter criteria" do
          query = "some_query ecosystem:RubyGems ecosystem:npm relationship:direct relationship:transitive"
          query_builder = @builder.new(query: query)
          assert_equal "some_query relationship:transitive ecosystem:npm", query_builder.raw_query
        end

        test "should return the last valid relationship value" do
          query = "some_query relationship:direct relationship:invalid"
          query_builder = @builder.new(query: query)
          assert_equal "direct", query_builder.relationship
        end

        test "should return the last valid ecosystem value" do
          query = "some_query ecosystem:RubyGems ecosystem:invalid"
          query_builder = @builder.new(query: query)
          assert_equal "RubyGems", query_builder.ecosystem
        end

        test "should only return the valid criterion value in query" do
          query = "some_query ecosystem:invalid relationship:invalid"
          query_builder = @builder.new(query: query)
          assert_equal "some_query", query_builder.raw_query
        end

        test "should correctly return the last ecosystem value with quotes" do
          query = "some_query ecosystem:\"GitHub Actions\" ecosystem:\"GitHub Actions\""
          query_builder = @builder.new(query: query)
          assert_equal "some_query ecosystem:\"GitHub Actions\"", query_builder.raw_query
        end

        test "toggle ecosystem should add ecosystem if none exists" do
          query_builder = @builder.new(query: "some existing query")
          result = query_builder.toggle_ecosystem("npm")
          assert_equal "some existing query ecosystem:npm", result
        end

        test "toggle ecosystem should remove ecosystem if it exists" do
          query_builder = @builder.new(query: "some ecosystem:npm other query")
          result = query_builder.toggle_ecosystem("npm")
          assert_equal "some other query", result
        end

        test "toggle ecosystem should replace any non-matching ecosystem if present" do
          query_builder = @builder.new(query: "relationship:direct ecosystem:RubyGems this should remain")
          result = query_builder.toggle_ecosystem("npm")
          assert_equal "this should remain relationship:direct ecosystem:npm", result
        end

        test "toggle ecosystem should wrap ecosystem with spaces in quotes" do
          query_builder = @builder.new(query: "some existing query")
          result = query_builder.toggle_ecosystem("GitHub Actions")
          assert_equal "some existing query ecosystem:\"GitHub Actions\"", result
        end

        test "toggle ecosystem should untoggle ecosystem with spaces in quotes" do
          query_builder = @builder.new(query: "some existing query ecosystem:\"GitHub Actions\"")
          result = query_builder.toggle_ecosystem("GitHub Actions")
          assert_equal "some existing query", result
        end

        test "should remove negated criterion" do
          query_builder = @builder.new(query: "some search -ecosystem:npm -relationship:direct")
          assert_equal "some search", query_builder.raw_query
        end

        test "should remove negated criterion and retain valid criterion" do
          query_builder = @builder.new(query: "some search -ecosystem:npm ecosystem:npm")
          assert_equal "some search ecosystem:npm", query_builder.raw_query
        end
      end
    end
  end
end
