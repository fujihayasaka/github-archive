# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

FullCodeOfConductQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query {
    codeOfConduct(key: "contributor_covenant") {
      ...Api::Serializer::CodesOfConductDependency::FullCodeOfConductFragment
    }
  }
GRAPHQL

PartialCodeOfConductQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query {
    codeOfConduct(key: "contributor_covenant") {
      ...Api::Serializer::CodesOfConductDependency::PartialCodeOfConductFragment
    }
  }
GRAPHQL

PartialRepositoryCodeOfConductQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
query($id: ID!) {
  node(id: $id) {
    ...Api::Serializer::CodesOfConductDependency::PartialCodeOfConductFragment
  }
}
GRAPHQL

FullRepositoryCodeOfConductQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
  query($id: ID!) {
    node(id: $id) {
      ...Api::Serializer::CodesOfConductDependency::FullCodeOfConductFragment
    }
  }
GRAPHQL

class CodeOfConductSerializersTest < Api::SerializerTestCase
  fixtures do
    @person = create(:user)
    @repo_with_code_of_conduct = create :repository, owner: @person, from_example: :code_of_conduct_markdown
  end

  context "#code_of_conduct_hash" do
    test "renders a code of conduct" do
      coc    = CodeOfConduct.find(:contributor_covenant)
      output = code_of_conduct(coc)
      assert output.key?("key")
      assert output.key?("name")
      assert output.key?("html_url")
      assert output.key?("url")
    end

    test "renders a full code of conduct" do
      coc    = CodeOfConduct.find(:contributor_covenant)
      output = code_of_conduct(coc, full: true)
      assert_equal coc.body, output["body"]
    end

    test "renders a RepositoryCodeOfConduct" do
      repo_code_of_conduct = @repo_with_code_of_conduct.code_of_conduct
      output = code_of_conduct(repo_code_of_conduct)
      assert output.key?("key")
      assert output.key?("name")
      assert output.key?("html_url")
      assert output.key?("url")
    end

    test "renders a full RepositoryCodeOfConduct" do
      repo_code_of_conduct = @repo_with_code_of_conduct.code_of_conduct
      output = code_of_conduct(repo_code_of_conduct, full: true)
      assert_equal repo_code_of_conduct.body, output["body"]
    end
  end

  context "#graphql_code_of_conduct_hash" do
    test "renders a code of conduct" do
      coc = CodeOfConduct.find(:contributor_covenant)
      results = Api::App::PlatformClient.query(PartialCodeOfConductQuery, context: { viewer: @person })
      gql_output = graphql_code_of_conduct(results.data.code_of_conduct)
      rest_output = code_of_conduct(coc)

      assert_equal rest_output, gql_output
    end

    test "renders a full code of conduct" do
      coc     = CodeOfConduct.find(:contributor_covenant)
      results = Api::App::PlatformClient.query(FullCodeOfConductQuery, context: { viewer: @person })
      gql_output = graphql_code_of_conduct(results.data.code_of_conduct, full: true)
      rest_output = code_of_conduct(coc, full: true)

      assert_equal rest_output, gql_output
    end

    test "renders a RepositoryCodeOfConduct" do
      repo_code_of_conduct = @repo_with_code_of_conduct.code_of_conduct
      results = Api::App::PlatformClient.query(PartialRepositoryCodeOfConductQuery, context: { viewer: @person }, variables: { "id" => repo_code_of_conduct.global_relay_id })
      gql_output = graphql_code_of_conduct(results.data.node)
      rest_output = code_of_conduct(repo_code_of_conduct)

      assert_equal rest_output, gql_output
    end

    test "renders a full RepositoryCodeOfConduct" do
      repo_code_of_conduct = @repo_with_code_of_conduct.code_of_conduct
      results = Api::App::PlatformClient.query(FullRepositoryCodeOfConductQuery, context: { viewer: @person }, variables: { "id" => repo_code_of_conduct.global_relay_id })
      gql_output = graphql_code_of_conduct(results.data.node, full: true)
      rest_output = code_of_conduct(repo_code_of_conduct, full: true)

      assert_equal rest_output, gql_output
    end
  end
end
