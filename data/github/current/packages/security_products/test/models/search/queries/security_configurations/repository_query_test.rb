# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityConfigurationsRepositoryQueryTest < GitHub::TestCase
  context "#es_query_string" do
    test "returns a query string that can be supported by Elasticsearch" do
      query = "visibility:public,internal configuration:\"High risk\" config-status:attached,removed props.environment:dev,test sort:updated"

      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:).es_query_string
      assert_equal "visibility:public,internal props.environment:dev,test sort:updated archived:false", result
    end
  end

  context "#mysql_query_hash" do
    test "returns a hash of filters that can be supported by MySQL" do
      query = "visibility:public,internal configuration:\"High risk\" config-status:attached,removed props.environment:dev,test sort:updated"

      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:).mysql_query_hash
      assert_equal({ "configuration" => ["High risk"], "config-status" => %w(attached removed) }, result)
    end

    test "returns a hash of negated filters that can be supported by MySQL" do
      query = "visibility:public,internal -configuration:\"High risk\" -config-status:attached,removed props.environment:dev,test sort:updated"

      result = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:).mysql_query_hash
      assert_equal({ "-configuration" => ["High risk"], "-config-status" => %w(attached removed) }, result)
    end
  end
end
