# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class ReactionsTest < Api::SerializerTestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @issue_comment = create(:issue_comment, user: @user)
    @reaction = @issue_comment.react(actor: @user, content: "smile")
  end

  ReactionQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      node(id: $id) {
        ... on Reaction {
          ...Api::Serializer::ReactionsDependency::ReactionFragment
        }
      }
    }
  GRAPHQL

  context "#reaction_hash" do
    test "payload is valid" do
      output = T.unsafe(self).reaction(@reaction)
      assert_same_elements %w[id node_id user content created_at], output.keys
    end
  end

  context "#graphql_reaction_hash" do
    test "payload is valid" do
      results = Api::App::PlatformClient.query(ReactionQuery, variables: { id: @reaction.global_relay_id }, context: { viewer: @user })
      output = T.unsafe(self).graphql_reaction(results.data.node)
      assert_same_elements %w[id node_id user content created_at], output.keys
    end
  end
end
