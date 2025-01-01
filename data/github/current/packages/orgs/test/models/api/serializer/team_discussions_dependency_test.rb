# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class TeamDiscussionSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  DiscussionQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      discussion: node(id: $id) {
        ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionFragment
      }
    }
  GRAPHQL

  CommentQuery = Api::App::PlatformClient.parse(<<-'GRAPHQL')
    query($id: ID!) {
      comment: node(id: $id) {
        ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionCommentFragment
      }
    }
  GRAPHQL

  fixtures do
    @team = create :team, privacy: :closed
    @discussion = create :discussion_post, team: @team
    @comment = create :discussion_post_reply, discussion_post: @discussion
    @org_member = create(:user, login: "org-member")
    @team.organization.add_member(@org_member)

    @hearts = 2.times.map do
      create :reaction, subject: @discussion, content: "heart"
    end
    @laughs = 3.times.map do
      create :reaction, subject: @discussion, content: "smile"
    end
    @boosts = 3.times.map { create :reaction, subject: @comment, content: "+1" }
  end

  context "#graphql_team_discussion_hash" do
    test "serializes URLs correctly" do
      result = Api::App::PlatformClient.query(
        DiscussionQuery,
        context: { viewer: @org_member },
        variables: { "id" => @discussion.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_hash,
        result.data.discussion)

      assert_equal(
        output[:url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/#{@discussion.number}",
        "did not serialize discussion API url correctly")
      assert_equal(
        output[:html_url],
        "#{GitHub.url}/orgs/#{@team.organization}/teams/#{@team.slug}/" +
          "discussions/#{@discussion.number}",
        "did not serialize discussion .com url correctly")
      assert_equal(
        output[:comments_url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/" +
          "#{@discussion.number}/comments",
        "did not serialize comments API url correctly")
      assert_equal(
        output[:team_url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}",
        "did not serialize team API url correctly")
    end

    test "includes last_edited_at timestamp when discussion has been edited" do
      @discussion.update_body("something else", @discussion.user)
      @discussion.save!

      result = Api::App::PlatformClient.query(
        DiscussionQuery,
        context: { viewer: @org_member },
        variables: { "id" => @discussion.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_hash,
        result.data.discussion)

      assert output[:last_edited_at]
    end

    test "includes reactions given correct preview header" do
      result = Api::App::PlatformClient.query(
        DiscussionQuery,
        context: { viewer: @org_member },
        variables: { "id" => @discussion.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_hash, result.data.discussion)

      assert output[:reactions]
      assert_equal(
        output[:reactions][:url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/" +
        "#{@discussion.number}/reactions")
      assert_equal (@hearts + @laughs).length, output[:reactions][:total_count]
      assert_equal @hearts.length, output[:reactions][:heart]
      assert_equal @laughs.length, output[:reactions][:laugh]

      other_reaction_counts = output[:reactions]
        .except(:url, :total_count, :laugh, :heart)
        .values
      assert_equal(0, other_reaction_counts.sum)
    end
  end

  context "#graphql_team_discussion_comment_hash" do
    test "serializes URLs correctly" do
      result = Api::App::PlatformClient.query(
        CommentQuery,
        context: { viewer: @org_member },
        variables: { "id" => @comment.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_comment_hash,
        result.data.comment)

      assert_equal(
        output[:url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/" +
          "#{@discussion.number}/comments/#{@comment.number}",
        "did not serialize comment API url correctly")
      assert_equal(
        output[:html_url],
        "#{GitHub.url}/orgs/#{@team.organization}/teams/#{@team.slug}/" +
          "discussions/#{@discussion.number}/comments/#{@comment.number}",
        "did not serialize comment .com url correctly")
      assert_equal(
        output[:discussion_url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/#{@discussion.number}",
        "did not serialize discussion API url correctly")
    end

    test "includes last_edited_at timestamp when comment has been edited" do
      @comment.update_body("something else", @comment.user)
      @comment.save!

      result = Api::App::PlatformClient.query(
        CommentQuery,
        context: { viewer: @org_member },
        variables: { "id" => @comment.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_comment_hash,
        result.data.comment)

      assert output[:last_edited_at]
    end

    test "includes reactions given correct preview header" do
      result = Api::App::PlatformClient.query(
        CommentQuery,
        context: { viewer: @org_member },
        variables: { "id" => @comment.global_relay_id })

      output = Api::Serializer.serialize(:graphql_team_discussion_comment_hash, result.data.comment)

      assert output[:reactions]
      assert_equal(
        output[:reactions][:url],
        "#{GitHub.api_url}/organizations/#{@team.organization_id}/team/#{@team.id}/discussions/" +
        "#{@discussion.number}/comments/#{@comment.number}/reactions")
      assert_equal @boosts.length, output[:reactions][:total_count]
      assert_equal @boosts.length, output[:reactions][:"+1"]

      other_reaction_counts = output[:reactions]
        .except(:url, :total_count, :"+1")
        .values
      assert_equal(0, other_reaction_counts.sum)
    end
  end
end
