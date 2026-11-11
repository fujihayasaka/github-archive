# frozen_string_literal: true
require "test_helper"
require_relative "../../base_generator_test"
require "generators/graphql/cancan/install_generator"

class GraphQLGeneratorsCancanInstallGeneratorTest < BaseGeneratorTest
  tests Graphql::Generators::Cancan::InstallGenerator

  def setup
    FileUtils.rm_rf("tmp/app")
    FileUtils.cp_r("test/support/rails_dummy/app", "tmp/")
  end

  def test_it_injects_code_into_base_classes
    run_generator
    assert_file "app/graphql/types/base_object.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::ObjectIntegration
    # Add a default ability here, or `nil` to require nothing by default:
    # can_can_action :read
"
    end

    assert_file "app/graphql/types/base_union.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::UnionIntegration
"
    end

    assert_file "app/graphql/resolvers/base_resolver.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::ResolverIntegration
"
    end

    assert_file "app/graphql/mutations/base_mutation.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::MutationIntegration
"
    end

    assert_file "app/graphql/types/base_interface.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Schema::Interface
    include GraphQL::Pro::CanCanIntegration::InterfaceIntegration
"
    end

    assert_file "app/graphql/types/base_field.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::FieldIntegration
    # Add a default ability here, or `nil` to require nothing by default:
    # can_can_action :read
"
    end

    assert_file "app/graphql/types/base_argument.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::CanCanIntegration::ArgumentIntegration
    # Add a default ability here, or `nil` to require nothing by default:
    # can_can_action :read
"
    end
  end
end
