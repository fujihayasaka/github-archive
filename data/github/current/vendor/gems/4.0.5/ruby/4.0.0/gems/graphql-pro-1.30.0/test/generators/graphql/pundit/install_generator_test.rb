# frozen_string_literal: true
require "test_helper"
require_relative "../../base_generator_test"
require "generators/graphql/pundit/install_generator"

class GraphQLGeneratorsPunditInstallGeneratorTest < BaseGeneratorTest
  tests Graphql::Generators::Pundit::InstallGenerator

  def setup
    FileUtils.rm_rf("tmp/app")
    FileUtils.cp_r("test/support/rails_dummy/app", "tmp/")
  end

  def test_it_injects_code_into_base_classes
    run_generator
    assert_file "app/graphql/types/base_object.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::ObjectIntegration
    # Add a default role here, or `nil` to disable authorization by default:
    # pundit_role :viewer
"
    end

    assert_file "app/graphql/types/base_union.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::UnionIntegration
"
    end

    assert_file "app/graphql/resolvers/base_resolver.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::ResolverIntegration
"
    end

    assert_file "app/graphql/mutations/base_mutation.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::MutationIntegration
"
    end

    assert_file "app/graphql/types/base_interface.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Schema::Interface
    include GraphQL::Pro::PunditIntegration::InterfaceIntegration
"
    end

    assert_file "app/graphql/types/base_field.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::FieldIntegration
    # Add a default role here, or `nil` to disable authorization by default:
    # pundit_role :viewer
"
    end

    assert_file "app/graphql/types/base_argument.rb" do |contents|
      assert_includes contents, "
    include GraphQL::Pro::PunditIntegration::ArgumentIntegration
    # Add a default role here, or `nil` to disable authorization by default:
    # pundit_role :viewer
"
    end
  end
end
