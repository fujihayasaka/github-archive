# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityConfigurationsRepositoryQueryTest < GitHub::TestCase
  context "query strings" do
    test "separates a query string into qualifiers that are handled by MySQL and ElasticSearch" do
      query = "visibility:public,internal configuration:\"High risk\" config-status:attached,removed props.environment:dev,test sort:updated"
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      assert_equal("visibility:public,internal sort:updated archived:false props.environment:dev,test", result.es_query_string)
      assert_equal({ "configuration" => ["High risk"], "config-status" => %w(attached removed) }, result.mysql_query_hash)
    end

    test "supports negated filters" do
      query = "-visibility:public,internal -configuration:\"High risk\" -config-status:attached,removed props.environment:dev,test sort:updated"
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      assert_equal("-visibility:public,internal sort:updated archived:false props.environment:dev,test", result.es_query_string)
      assert_equal({ "-configuration" => ["High risk"], "-config-status" => %w(attached removed) }, result.mysql_query_hash)
    end

    test "supports advanced filters" do
      query = "visibility:public,internal configuration:\"High risk\" -advanced-security:enabled code-scanning-default-setup:disabled,not-eligible"
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      expected = {
        "configuration" => ["High risk"],
        "advanced_filters" => "-advanced-security:enabled code-scanning-default-setup:not-enabled,not-eligible"
      }
      assert_equal("visibility:public,internal archived:false", result.es_query_string)
      assert_equal(expected, result.mysql_query_hash)
    end

    test "correctly parses configuration names with commas 1" do
      query = 'configuration:"High risk, low risk"'
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      assert_equal("archived:false", result.es_query_string)
      assert_equal({ "configuration" => ["High risk, low risk"] }, result.mysql_query_hash)
    end

    test "correctly parses configuration names with commas 2" do
      query = 'configuration:"High risk, low risk",Medium'
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      assert_equal("archived:false", result.es_query_string)
      assert_equal({ "configuration" => ["High risk, low risk", "Medium"] }, result.mysql_query_hash)
    end

    test "correctly parses configuration names with commas 3" do
      query = 'configuration:"High risk, low risk",Medium config-status:removed,failed'
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      expected = { "configuration" => ["High risk, low risk", "Medium"], "config-status" => %w(removed failed) }
      assert_equal("archived:false", result.es_query_string)
      assert_equal(expected, result.mysql_query_hash)
    end

    test "can handle multiple repo properties that contain spaces" do
      query = 'visibility:public,internal props.PCI-DSS:"Enabled (Arctic Ruleset)","Enabled (Default Ruleset)","Enabled (Grey Zone Ruleset)"'
      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

      assert_equal 'visibility:public,internal archived:false props.PCI-DSS:"Enabled (Arctic Ruleset)","Enabled (Default Ruleset)","Enabled (Grey Zone Ruleset)"', result.es_query_string
      assert_empty result.mysql_query_hash
    end
  end
end
