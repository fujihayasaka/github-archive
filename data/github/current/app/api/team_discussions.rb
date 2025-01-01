# typed: false
# frozen_string_literal: true

class Api::TeamDiscussions < Api::App
  include ::Api::App::TeamDiscussionHelpers
  include ReceiveSchemaWithOpenApi

  before "/organizations/:org_id/team/:team_id/discussions*" do
    deliver_error!(404) if changeset_active?(:remove_team_discussions)

    if GitHub.enterprise?
      deprecated(
        deprecation_date: Time.new(2024, 2, 27),
        sunset_date: Time.new(2024, 2, 27),
        info_url: ""
      )
    else
      deprecated(
        deprecation_date: Time.new(2023, 7, 5),
        sunset_date: Time.new(2023, 7, 5),
        info_url: "https://github.blog/changelog/2023-02-08-sunset-notice-team-discussions/"
      )
    end

    organization = Organization.find_by(id: int_id_param!(key: :org_id))
    record_or_404(organization)
    @team = organization.teams.find_by(id: int_id_param!(key: :team_id))
    record_or_404(team)

    if @team.migration_complete
      deliver_error!(410,
        message: "Team discussions are disabled for this team due to discussions migration.")
    end

    unless organization.team_discussions_allowed?
      deliver_error!(410,
        message: "Team discussions are disabled for this organization.",
        documentation_url: "/v3/teams/discussions")
    end

    # Something deep in the guts of GitHub Apps authz requires
    # this to be set.
    @current_org = organization
  end

  ListDiscussionsQuery = PlatformClient.parse <<-'GRAPHQL'
    query(
      $teamId: ID!,
      $pinned: Boolean,
      $limit: Int!,
      $numericPage: Int,
      $direction: OrderDirection!) {
      team: node(id: $teamId) {
        ... on Team {
          discussions(
            isPinned: $pinned,
            first: $limit,
            numericPage: $numericPage,
            orderBy: {field: CREATED_AT, direction: $direction}) {
            nodes {
              ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionFragment
            }
            totalCount
          }
        }
      }
    }
  GRAPHQL

  get "/organizations/:org_id/team/:team_id/discussions", operation_ids: ["teams/list-discussions-in-org", "teams/list-discussions-legacy"] do
    control_access(
      :list_team_discussions,
      organization: team.organization,
      resource: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = {
      teamId: team.global_relay_id,
      pinned: params[:pinned] && params[:pinned] == "1",
      limit: per_page,
      numericPage: pagination[:page],
      direction: sort_direction,
    }

    results = platform_execute(ListDiscussionsQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: results.errors.all,
        resource: "TeamDiscussion",
        documentation_url: @documentation_url,
      })
    end

    discussions = results.data.team.discussions

    paginator.collection_size = discussions.total_count
    deliver :graphql_team_discussion_hash, discussions.nodes
  end

  CreateDiscussionMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: CreateTeamDiscussionInput!) {
      createTeamDiscussion(input: $input)  {
        teamDiscussion {
          ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionFragment
        }
      }
    }
  GRAPHQL

  post "/organizations/:org_id/team/:team_id/discussions", operation_ids: ["teams/create-discussion-in-org", "teams/create-discussion-legacy"] do
    control_access(
      :create_team_discussion,
      organization: team.organization,
      resource: team,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    data = receive_with_schema("team-discussion", "create-legacy")

    variables = {
      input: {
        body: data["body"],
        private: data["private"],
        teamId: team.global_relay_id,
        title: data["title"],
      },
    }

    result = platform_execute(CreateDiscussionMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussion",
        documentation_url: @documentation_url,
      })
    end

    deliver(
      :graphql_team_discussion_hash,
      result.data.create_team_discussion.team_discussion,
      status: 201)
  end

  UpdateDiscussionMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: UpdateTeamDiscussionInput!) {
      updateTeamDiscussion(input: $input)  {
        teamDiscussion {
          ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionFragment
        }
      }
    }
  GRAPHQL

  patch "/organizations/:org_id/team/:team_id/discussions/:discussion_number", operation_ids: ["teams/update-discussion-in-org", "teams/update-discussion-legacy"] do
    discussion = find_discussion!

    control_access(
      :update_team_discussion,
      organization: team.organization,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    data = receive_with_schema("team-discussion", "update-legacy")

    variables = {
      input: {
        body: data["body"],
        bodyVersion: data["body_version"],
        id: discussion.global_relay_id,
        pinned: data["pinned"],
        title: data["title"],
      },
    }

    result = platform_execute(UpdateDiscussionMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussion",
        documentation_url: @documentation_url,
      })
    end

    deliver(
      :graphql_team_discussion_hash,
      result.data.update_team_discussion.team_discussion)
  end

  ShowDiscussionQuery = PlatformClient.parse <<-'GRAPHQL'
    query($discussionId: ID!) {
      node(id: $discussionId) {
        ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionFragment
      }
    }
  GRAPHQL

  get "/organizations/:org_id/team/:team_id/discussions/:discussion_number", operation_ids: ["teams/get-discussion-in-org", "teams/get-discussion-legacy"] do
    discussion = find_discussion!

    control_access(
      :show_team_discussion,
      organization: team.organization,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = { discussionId: discussion.global_relay_id }
    result = platform_execute(ShowDiscussionQuery, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussion",
        documentation_url: @documentation_url,
      })
    end

    deliver(:graphql_team_discussion_hash, result.data.node)
  end

  DeleteDiscussionMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: DeleteTeamDiscussionInput!) {
      deleteTeamDiscussion(input: $input)
    }
  GRAPHQL

  delete "/organizations/:org_id/team/:team_id/discussions/:discussion_number", operation_ids: ["teams/delete-discussion-in-org", "teams/delete-discussion-legacy"] do
    # Introducing strict validation of the team-discussion.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("team-discussion", "delete", skip_validation: true)

    discussion = find_discussion!

    control_access(
      :delete_team_discussion,
      organization: team.organization,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = { input: { id: discussion.global_relay_id } }
    result = platform_execute(DeleteDiscussionMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussion",
        documentation_url: @documentation_url,
      })
    end

    deliver_empty status: 204
  end

  ListCommentsQuery = PlatformClient.parse <<-'GRAPHQL'
    query(
      $discussionId: ID!,
      $limit: Int!,
      $numericPage: Int
      $direction: OrderDirection!) {
      discussion: node(id: $discussionId) {
        ... on TeamDiscussion {
          comments(
            first: $limit,
            numericPage: $numericPage,
            orderBy: {field: NUMBER, direction: $direction}) {
            nodes {
              ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionCommentFragment
            }
            totalCount
          }
        }
      }
    }
  GRAPHQL

  get "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments", operation_ids: ["teams/list-discussion-comments-in-org", "teams/list-discussion-comments-legacy"] do
    discussion = find_discussion!

    control_access(
      :list_team_discussion_comments,
      organization: team.organization,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = {
      discussionId: discussion.global_relay_id,
      limit: per_page,
      numericPage: pagination[:page],
      direction: sort_direction,
    }

    results = platform_execute(ListCommentsQuery, variables: variables)

    if results.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: results.errors.all,
        resource: "TeamDiscussionComment",
        documentation_url: @documentation_url,
      })
    end

    comments = results.data.discussion.comments

    paginator.collection_size = comments.total_count
    deliver :graphql_team_discussion_comment_hash, comments.nodes
  end

  ShowCommentQuery = PlatformClient.parse <<-'GRAPHQL'
    query($commentId: ID!) {
      comment: node(id: $commentId) {
        ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionCommentFragment
      }
    }
  GRAPHQL

  get "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number", operation_ids: ["teams/get-discussion-comment-in-org", "teams/get-discussion-comment-legacy"] do
    comment = find_discussion_comment!

    # Make an exception to the platform enforcement rule to allow loading of the
    # parent discussion object in the `comment.readable_by?(user)` call that
    # is issued due to passing `resource: comment` to `control_access`.
    control_access(
      :show_team_discussion_comment,
      organization: team.organization,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = { commentId: comment.global_relay_id }
    result = platform_execute(ShowCommentQuery, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussionComment",
        documentation_url: @documentation_url,
      })
    end

    deliver(:graphql_team_discussion_comment_hash, result.data.comment)
  end

  CreateCommentMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: CreateTeamDiscussionCommentInput!) {
      createTeamDiscussionComment(input: $input)  {
        teamDiscussionComment {
          ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionCommentFragment
        }
      }
    }
  GRAPHQL

  post "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments", operation_ids: ["teams/create-discussion-comment-in-org", "teams/create-discussion-comment-legacy"] do
    discussion = find_discussion!

    control_access(
      :create_team_discussion_comment,
      organization: team.organization,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    data = receive_with_schema("team-discussion-comment", "create-legacy")
    variables = {
      input: {
        discussionId: discussion.global_relay_id,
        body: data["body"],
      },
    }
    result = platform_execute(CreateCommentMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussionComment",
        documentation_url: @documentation_url,
      })
    end

    deliver(
      :graphql_team_discussion_comment_hash,
      result.data.create_team_discussion_comment.team_discussion_comment,
      status: 201)
  end

  UpdateCommentMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: UpdateTeamDiscussionCommentInput!) {
      updateTeamDiscussionComment(input: $input)  {
        teamDiscussionComment {
          ...Api::Serializer::TeamDiscussionsDependency::TeamDiscussionCommentFragment
        }
      }
    }
  GRAPHQL

  patch "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number", operation_ids: ["teams/update-discussion-comment-in-org", "teams/update-discussion-comment-legacy"] do
    comment = find_discussion_comment!

    # Make an exception to the platform enforcement rule to allow loading of the
    # parent discussion object in the `comment.readable_by?(user)` call that
    # is issued due to passing `resource: comment` to `control_access`.
    control_access(
      :update_team_discussion_comment,
      organization: team.organization,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    data = receive_with_schema("team-discussion-comment", "update-legacy")
    variables = {
      input: {
        id: comment.global_relay_id,
        body: data["body"],
        bodyVersion: data["body_version"],
      },
    }
    result = platform_execute(UpdateCommentMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussionComment",
        documentation_url: @documentation_url,
      })
    end

    deliver(
      :graphql_team_discussion_comment_hash,
      result.data.update_team_discussion_comment.team_discussion_comment)
  end

  DeleteCommentMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: DeleteTeamDiscussionCommentInput!) {
      deleteTeamDiscussionComment(input: $input)
    }
  GRAPHQL

  delete "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number", operation_ids: ["teams/delete-discussion-comment-in-org", "teams/delete-discussion-comment-legacy"] do
    # Introducing strict validation of the team-discussion-comment.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("team-discussion-comment", "delete", skip_validation: true)

    comment = find_discussion_comment!

    # Make an exception to the platform enforcement rule to allow loading of the
    # parent discussion object in the `comment.readable_by?(user)` call that
    # is issued due to passing `resource: comment` to `control_access`.
    control_access(
      :delete_team_discussion_comment,
      organization: team.organization,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    variables = { input: { id: comment.global_relay_id } }
    result = platform_execute(DeleteCommentMutation, variables: variables)

    if result.errors.all.any?
      deprecated_deliver_graphql_error!({
        errors: result.errors.all,
        resource: "TeamDiscussionComment",
        documentation_url: @documentation_url,
      })
    end

    deliver_empty status: 204
  end

  private def sort_direction
    params[:direction]&.downcase == "asc" ? "ASC" : "DESC"
  end
end
