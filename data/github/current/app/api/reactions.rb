# typed: true
# frozen_string_literal: true

class Api::Reactions < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::DatabaseConnectionHelper
  include Api::App::TeamDiscussionHelpers
  include Api::Issues::EnsureIssuesEnabled

  before "/organizations/:org_id/team/:team_id/discussions/:number/*" do
    organization = Organization.find_by(id: int_id_param!(key: :org_id))
    record_or_404(organization)
    @team = T.must(organization).teams.find_by(id: int_id_param!(key: :team_id))
    record_or_404(team)

    unless T.must(organization).team_discussions_allowed?
      deliver_error!(410,
        message: "Team discussions are disabled for this organization.",
        documentation_url: "/v3/teams/discussions")
    end

    # Something deep in the guts of GitHub Apps authz requires
    # this to be set.
    @current_org = organization
  end

  ListReactionsQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
    query($issueId: ID!, $content: ReactionContent, $limit: Int!, $numericPage: Int) {
      node(id: $issueId) {
        ... on Issue {
          reactions(
            content: $content,
            first: $limit,
            numericPage: $numericPage) {
            nodes {
              ...Api::Serializer::ReactionsDependency::ReactionFragment
            }
            totalCount
          }
        }
        ... on PullRequest {
          reactions(
            content: $content,
            first: $limit,
            numericPage: $numericPage) {
            nodes {
              ...Api::Serializer::ReactionsDependency::ReactionFragment
            }
            totalCount
          }
        }
      }
    }
  GRAPHQL

  # List Reactions for this Issue
  get "/repositories/:repository_id/issues/:issue_number/reactions", operation_id: "reactions/list-for-issue" do
    repo = find_repo!
    issue = repo.issues.find_by_number(int_id_param!(key: :issue_number)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    record_or_404(issue)
    set_context_controller_action(issue, "list-reactions")


    control_access :show_issue,
      resource: issue,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr!(repo, issue)

    variables = {
      issueId: issue.global_relay_id,
      limit: pagination[:per_page] || DEFAULT_PER_PAGE,
      numericPage: pagination[:page],
    }

    if (filter = params[:content].presence) && (emotion = Emotion.find_by_label(filter.downcase))
      variables[:content] = emotion.platform_enum
    end

    results = platform_execute(ListReactionsQuery, variables: variables)

    if results.errors.all.any?
      errors = results.errors.all.details["data"]
      error_types = errors.map { |err| err["type"] }
      if !(error_types & %w(NOT_FOUND UNAUTHENTICATED)).empty?
        deliver_error! 404, message: "Not Found", documentation_url: @documentation_url
      elsif error_types.any? { |err| err == "ISSUES_DISABLED" }
        deliver_error! 410, message: "Issues are disabled for this repo", documentation_url: @documentation_url
      else
        deliver_error! 422, errors: results.errors.values.flatten
      end
    end

    reactions = results.data.node.reactions

    paginator.collection_size = reactions.total_count
    deliver :graphql_reaction_hash, reactions.nodes
  end

  # Create Reaction for this Issue
  post "/repositories/:repository_id/issues/:issue_number/reactions", operation_id: "reactions/create-for-issue" do
    replica_clusters = T.let([ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = find_repo!
      issue = repo.issues.find_by_number(int_id_param!(key: :issue_number)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      record_or_404(issue)
      set_context_controller_action(issue, "create-reaction")


      control_access :create_issue_related_reaction,
        resource: issue,
        repo: repo,
        challenge: repo.public?,
        enforce_oauth_app_policy: repo.private?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true

      authorize_content :issue, repo: repo
      ensure_content_visible issue

      data = receive_with_schema("reaction", "create-for-issue-legacy")
      reaction = Reaction.react user: current_user,
        subject_id: issue.id,
        subject_type: issue.class.name,
        content: Emotion.find_by_label(data["content"]).content

      deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
      deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

      deliver_error!(422, errors: reaction.errors)
    end
  end

  delete "/repositories/:repository_id/issues/:issue_number/reactions/:reaction_id", operation_id: "reactions/delete-for-issue" do
    replica_clusters = T.let([ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = find_repo!
      issue = repo.issues.find_by_number(int_id_param!(key: :issue_number)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      record_or_404(issue)
      set_context_controller_action(issue, "delete-reaction")


      receive_with_schema("reaction", "delete")
      reaction = issue.reactions.find_by(id: int_id_param!(key: :reaction_id))
      record_or_404(reaction)

      control_access(
        :delete_reaction,
        reaction: reaction,
        resource: issue,
        repo: repo,
        challenge: true,
        forbid: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?,
      )

      Reaction.unreact(
        user: current_user,
        subject_id: reaction.subject_id,
        subject_type: reaction.subject_type,
        content: reaction.content)

      deliver_empty status: 204
    end
  end

  # List Reactions for this Issue Comment
  get "/repositories/:repository_id/issues/comments/:comment_id/reactions", operation_id: "reactions/list-for-issue-comment", resolve_tenant_context: :resolve_tenant_from_repo do
    repo    = find_repo!
    comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
    issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    set_context_controller_action(issue, "list-reactions-for-comment")

    control_access :get_issue_comment,
      repo: repo,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_content_visible comment

    scope = comment.reactions.not_spammy.reorder("id ASC")
    if (filter = params[:content].presence) && (emotion = Emotion.find_by_label(filter.downcase))
      scope = scope.where(content: emotion.content)
    end

    reactions = paginate_rel(scope)
    GitHub::PrefillAssociations.prefill_associations(reactions, :user)

    deliver :reaction_hash, reactions
  end

  # Create Reaction for this Issue Comment
  post "/repositories/:repository_id/issues/comments/:comment_id/reactions", operation_id: "reactions/create-for-issue-comment", resolve_tenant_context: :resolve_tenant_from_repo do
    replica_clusters = T.let([ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      set_context_controller_action(issue, "create-reaction-for-comment")

      control_access :create_issue_related_reaction,
        resource: comment,
        repo: repo,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?

      authorize_content :issue_comment, issue: issue, repo: repo
      ensure_content_visible comment

      data = receive_with_schema("reaction", "create-for-issue-comment-legacy")
      reaction = Reaction.react user: current_user,
        subject_id: comment.id,
        subject_type: comment.class.name,
        content: Emotion.find_by_label(data["content"]).content

      deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
      deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

      deliver_error!(422, errors: reaction.errors)
    end
  end

  delete "/repositories/:repository_id/issues/comments/:comment_id/reactions/:reaction_id", operation_id: "reactions/delete-for-issue-comment", resolve_tenant_context: :resolve_tenant_from_repo do
    replica_clusters = T.let([ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      set_context_controller_action(issue, "delete-reaction-for-comment")

      receive_with_schema("reaction", "delete")
      reaction = record_or_404 comment.reactions.find_by(id: int_id_param!(key: :reaction_id))

      control_access(
        :delete_reaction,
        reaction: reaction,
        resource: comment,
        repo: repo,
        challenge: true,
        forbid: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?,
      )

      Reaction.unreact(
        user: current_user,
        subject_id: reaction.subject_id,
        subject_type: reaction.subject_type,
        content: reaction.content)

      deliver_empty status: 204
    end
  end

  # List reactions for a Team Discussion
  get "/organizations/:org_id/team/:team_id/discussions/:discussion_number/reactions", operation_ids: ["reactions/list-for-team-discussion-in-org", "reactions/list-for-team-discussion-legacy"] do
    discussion = find_discussion!

    control_access(
      :show_team_discussion,
      resource: discussion,
      organization: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    scope = discussion.reactions.not_spammy.reorder("id ASC")
    if (filter = params[:content].presence) && (emotion = Emotion.find_by_label(filter.downcase))
      scope = scope.where(content: emotion.content)
    end

    reactions = paginate_rel(scope)
    GitHub::PrefillAssociations.prefill_associations(reactions, :user)

    deliver :reaction_hash, reactions
  end

  post "/organizations/:org_id/team/:team_id/discussions/:discussion_number/reactions", operation_ids: ["reactions/create-for-team-discussion-in-org", "reactions/create-for-team-discussion-legacy"] do
    discussion = find_discussion!

    # This code uses class methods like Reaction.user_can_react_to? and
    # Reaction.react, which all use ActiveRecord directly. Allow it as a one-off
    # direct access of Discussion{Post,PostReply} objects.
    control_access(
      :create_team_discussion_related_reaction,
      organization: current_org,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
    )

    data = receive_with_schema("reaction", "create-for-discussion-legacy")
    reaction = Reaction.react user: current_user,
      subject_id: discussion.id,
      subject_type: discussion.class.name,
      content: Emotion.find_by_label(data["content"]).content

    deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
    deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

    deliver_error!(422, errors: reaction.errors)
  end

  delete "/organizations/:org_id/team/:team_id/discussions/:discussion_number/reactions/:reaction_id", operation_id: "reactions/delete-for-team-discussion" do
    discussion = find_discussion!

    receive_with_schema("reaction", "delete")
    reaction = discussion.reactions.find_by(id: int_id_param!(key: :reaction_id))
    record_or_404(reaction)

    control_access(
      :delete_team_discussion_related_reaction,
      reaction: reaction,
      resource: discussion,
      organization: current_org,
      challenge: true,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    Reaction.unreact(
      user: current_user,
      subject_id: reaction.subject_id,
      subject_type: reaction.subject_type,
      content: reaction.content)

    deliver_empty status: 204
  end

  # List reactions for a Team Discussion Comment
  get "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number/reactions", operation_ids: ["reactions/list-for-team-discussion-comment-in-org", "reactions/list-for-team-discussion-comment-legacy"] do
    comment = find_discussion_comment!

    # Make an exception to the platform enforcement rule to allow loading of the
    # parent discussion object in the `comment.readable_by?(user)` call that
    # is issued due to passing `resource: comment` to `control_access`.
    control_access(
      :show_team_discussion_comment,
      resource: comment,
      organization: current_org,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    scope = comment.reactions.not_spammy.reorder("id ASC")
    if (filter = params[:content].presence) && (emotion = Emotion.find_by_label(filter.downcase))
      scope = scope.where(content: emotion.content)
    end

    reactions = paginate_rel(scope)
    GitHub::PrefillAssociations.prefill_associations(reactions, :user)

    deliver :reaction_hash, reactions
  end

  post "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number/reactions", operation_ids: ["reactions/create-for-team-discussion-comment-in-org", "reactions/create-for-team-discussion-comment-legacy"] do
    comment = find_discussion_comment!

    # This code uses class methods like Reaction.user_can_react_to? and
    # Reaction.react, which all use ActiveRecord directly. Allow it as a one-off
    # direct access of Discussion{Post,PostReply} objects.
    control_access(
      :create_team_discussion_related_reaction,
      organization: current_org,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    data = receive_with_schema("reaction", "create-for-discussion-comment-legacy")
    reaction = Reaction.react user: current_user,
      subject_id: comment.id,
      subject_type: comment.class.name,
      content: Emotion.find_by_label(data["content"]).content

    deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
    deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

    deliver_error!(422, errors: reaction.errors)
  end

  delete "/organizations/:org_id/team/:team_id/discussions/:discussion_number/comments/:comment_number/reactions/:reaction_id", operation_id: "reactions/delete-for-team-discussion-comment" do
    comment = find_discussion_comment!

    receive_with_schema("reaction", "delete")
    reaction = comment.reactions.find_by(id: int_id_param!(key: :reaction_id))
    record_or_404(reaction)

    control_access(
      :delete_team_discussion_related_reaction,
      reaction: reaction,
      resource: comment,
      organization: current_org,
      challenge: true,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true)

    Reaction.unreact(
      user: current_user,
      subject_id: reaction.subject_id,
      subject_type: reaction.subject_type,
      content: reaction.content)

    deliver_empty status: 204
  end

  def resolve_tenant_from_repo
    repo = find_repo!
    Business.find_by(id: repo.tenant_id)
  end

  private

  def authorize_content(kind, data = {})
    authorization = ContentAuthorizer.authorize(current_user, kind, "update", data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def ensure_content_visible(content)
    deliver_error!(404) if content.nil? || content.hide_from_user?(current_user)
  end
end
