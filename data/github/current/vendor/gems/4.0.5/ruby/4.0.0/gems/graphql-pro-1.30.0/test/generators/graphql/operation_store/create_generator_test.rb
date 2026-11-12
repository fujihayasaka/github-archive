# frozen_string_literal: true
require "test_helper"
require_relative "../../base_generator_test"
require "generators/graphql/operation_store/create_generator"

class GraphQLGeneratorsOperationStoreCreateGeneratorTest < BaseGeneratorTest
  tests Graphql::Generators::OperationStore::CreateGenerator

  def test_it_creates_a_migration_file
    run_generator
    assert_migration "db/migrate/setup_operation_store.rb" do |file_contents|
      assert_includes file_contents, "< ActiveRecord::Migration[#{Rails::VERSION::STRING.split(".").first(2).join(".")}]"
      assert_includes file_contents, "create_table :graphql_client_operations"
    end
  end
end
