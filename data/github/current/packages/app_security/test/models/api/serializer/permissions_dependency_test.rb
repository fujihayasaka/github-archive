# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class PermissionsTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @user = create(:user, login: "d12", plan: "pro")
    @rando = create(:user, login: "rando")

    @repo = create(:repository, :minimal, owner: @user)
    @repo.add_member(@rando)

    @integration  = create(:integration, owner: @user, name: "Public user app")
    @installation = @integration.install_on(@user, repositories: [@repo], installer: @user, entry_point: :test_case).installation
  end

  ViewerPermissionsRepositoryQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
    query($id: ID!) {
      node(id: $id) {
        ... on Repository {
          ...Api::Serializer::RepositoriesDependency::RepositoryPermissionFragment
        }
      }
    }
  GRAPHQL

  context "graphql_permissions_hash" do
    test "mirrors permissions_hash when object is a repository" do
      results = Api::App::PlatformClient.query(ViewerPermissionsRepositoryQuery, variables: { id: @repo.global_relay_id }, context: { viewer: @user })

      graphql_output = graphql_permissions(results.data.node)
      output = permissions(@repo, actor: @user)

      assert_equal output, graphql_output
    end

    test "returns nil when authed as a GitHub app" do
      results = Api::App::PlatformClient.query(ViewerPermissionsRepositoryQuery, variables: { id: @repo.global_relay_id }, context: { viewer: @installation.bot, integration: @integration })
      permissions_hash = graphql_permissions(results.data.node)

      output = permissions(@repo, actor: @installation.bot)

      assert_equal output, permissions_hash
    end
  end
end
