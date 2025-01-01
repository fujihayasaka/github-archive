# typed: true
# frozen_string_literal: true
require "scientist"

class Api::IssueComments < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::Limits
  include Api::App::UsersDependency
  include Api::App::DatabaseConnectionHelper
  include Issues::Domain::Provider

  # Get Comments for a Repo
  get "/repositories/:repository_id/issues/comments", operation_id: "issues/list-comments-for-repo" do
    repo = find_repo!
    control_access :list_all_issues_comments,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cap_paginated_entries!(ISSUES_PULL_REQUESTS_PAGINATION_LIMIT)

    pat_v2 = current_user && current_user.using_auth_via_granular_actor?

    issues_read = if pat_v2
      access_allowed?(:list_issues, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    else
      repo.resources.issues.readable_by?(current_user)
    end

    pull_requests_read = if pat_v2
      access_allowed?(:list_pull_requests, repo: repo, allow_integrations: true, allow_user_via_granular_actor: true)
    else
      repo.resources.pull_requests.readable_by?(current_user)
    end

    comments = get_comments(repo, issues_read, pull_requests_read)
    Reaction::Summary.prefill(comments)

    options = Api::SerializerOptions.fill(default_options)

    # only preload incase we need it later for serialization
    if preload_comments_edits?(options)
      GitHub::PrefillAssociations.prefill_batch_method(comments,
        :prelude_body_html,
        ::Feed::Cards::CommentBaseComponent::BODY_HTML_CONTEXT,
      )
    end

    GitHub.dogstats.time "prefill", tags: ["via:api", "action:repository_comments_list"] do
      deliver(:issue_comment_hash, comments, repo: repo)
    end
  end

  # Get Comments for an Issue
  get "/repositories/:repository_id/issues/:issue_number/comments", operation_id: "issues/list-comments", resolve_tenant_context: :resolve_tenant_from_repo do
    repo = find_repo!
    issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
    record_or_404(issue)
    issue = T.cast(issue, Issue)

    set_context_controller_action(issue, "list-comments")

    control_access :list_issue_comments,
      repo: repo,
      resource: issue,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_issues_enabled_or_pr! repo, issue

    scope = filter_and_sort(issue.comments.filter_spam_for(current_user)).
      includes(:issue).
      preload([:performed_via_integration, :user])
    comments = paginate_rel(scope)
    Reaction::Summary.prefill(comments)

    options = Api::SerializerOptions.fill(default_options)

    # only preload incase we need it later for serialization
    if preload_comments_edits?(options)
      GitHub::PrefillAssociations.prefill_batch_method(comments,
        :prelude_body_html,
        ::Feed::Cards::CommentBaseComponent::BODY_HTML_CONTEXT,
      )
    end

    GitHub.dogstats.time "prefill", tags: ["via:api", "action:issue_comments_list"] do
      deliver :issue_comment_hash, comments, repo: repo
    end
  end

  AddIssueCommentMutation = PlatformClient.parse <<-'GRAPHQL'
    mutation(
      $issueId: ID!,
      $body: String!,
      $clientMutationId: String!,
      $includeBody: Boolean!,
      $includeBodyHTML: Boolean!,
      $includeBodyText: Boolean!,
      $includePerformedViaGitHubApp: Boolean!
    ) {
      addComment(input: {
        subjectId: $issueId,
        body: $body,
        clientMutationId: $clientMutationId
      }) {
        commentEdge {
          comment: node {
            ...Api::Serializer::IssuesDependency::IssueCommentFragment
          }
        }
      }
    }
  GRAPHQL

  # Create a Comment for an Issue
  post "/repositories/:repository_id/issues/:issue_number/comments", operation_id: "issues/create-comment", resolve_tenant_context: :resolve_tenant_from_repo do
    with_replica_clusters([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities]) do
      repo  = find_repo!
      issue = issues_domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id)
      record_or_404(issue)
      issue = T.cast(issue, Issue)

      set_context_controller_action(issue, "create-comment")

      control_access :create_issue_comment,
        repo: repo,
        resource: issue,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        challenge: repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: repo.private?

      ensure_not_blocked! current_user, repo.owner_id
      authorize_content(:create, issue: issue, repo: repo)

      data = receive_with_schema("issue-comment", "create-legacy")

      input_variables = {
        issueId: issue.global_relay_id,
        body: data["body"],
        clientMutationId: request_id,
        includePerformedViaGitHubApp: true,
      }
      input_variables.update(graphql_mime_body_variables(default_options))

      results = platform_execute(AddIssueCommentMutation, variables: input_variables)

      if has_graphql_system_errors?(results)
        # The AddComment mutation doesn't support `UserErrors`, so we have to
        # manually map a 422 caused by hitting the rate limit to a 403
        if results.errors.all.first.include?(GitHub::RateLimitedCreation::ERROR_MESSAGE)
          if GitHub.flipper[:issue_comment_api_rate_limit_logging].enabled?(repo)
            log_rate_limited_request
          end

          deliver_error!(403, {
            message: ERROR_MESSAGE_RATE_LIMIT,
            documentation_url: DOC_URL_RATE_LIMIT,
          })
        else
          deprecated_deliver_graphql_error! errors: results.errors, resource: "IssueComment"
        end
      end

      comment = results.data.add_comment.comment_edge.comment
      deliver :graphql_issue_comment_hash, comment, status: 201
    end
  end

  ShowIssueCommentQuery = PlatformClient.parse <<-'GRAPHQL'
    query(
      $id:ID!,
      $includeBody:Boolean!,
      $includeBodyHTML:Boolean!,
      $includeBodyText:Boolean!,
      $includePerformedViaGitHubApp:Boolean!
    ) {
      comment: node(id:$id) {
        ...Api::Serializer::IssuesDependency::IssueCommentFragment
      }
    }
  GRAPHQL

  # View a single Issue Comment
  get "/repositories/:repository_id/issues/comments/:comment_id", operation_id: "issues/get-comment" do
    repo    = find_repo!
    comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
    issue   = record_or_404 comment.issue
    set_context_controller_action(issue, "get-comment")

    control_access :get_issue_comment,
      repo: repo,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if comment.hide_from_user?(current_user)
      deliver_error 404
    elsif !issue.pull_request? && !repo.has_issues?
      deliver_error 404
    else
      options = Api::SerializerOptions.fill(default_options)

      variables = {
        id: comment.global_relay_id,
        includePerformedViaGitHubApp: true,
      }
      variables.update(graphql_mime_body_variables(options))

      results = platform_execute(ShowIssueCommentQuery, variables: variables)
      comment = results.data.comment

      deliver :graphql_issue_comment_hash, comment
    end
  end

  verbs :patch, :post, "/repositories/:repository_id/issues/comments/:comment_id", operation_id: "issues/update-comment" do
    with_replica_clusters([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities]) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue
      set_context_controller_action(issue, "edit-comment")

      control_access :update_issue_comment,
        repo: repo,
        resource: comment,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        enforce_oauth_app_policy: repo.private?,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      authorize_content(:update, issue: comment.try(:issue), repo: repo)

      data = receive_with_schema("issue-comment", "update-legacy")

      if Issues::Comments.update_comment(comment, data["body"], current_user, performed_via_integration: current_integration)
        deliver :issue_comment_hash, comment, repo: repo
      else
        deliver_error 422,
          errors: comment.errors,
          documentation_url: @documentation_url
      end
    end
  end

  # Delete an Issue Comment
  delete "/repositories/:repository_id/issues/comments/:comment_id", operation_id: "issues/delete-comment" do
    # Introducing strict validation of the issue-comment.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("issue-comment", "delete", skip_validation: true)

    with_replica_clusters([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities]) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue
      set_context_controller_action(issue, "delete-comment")

      control_access :delete_issue_comment,
        repo: repo,
        resource: comment,
        challenge: repo.public?,
        # We only need to forbid in the case where a PAT or OAuth token does not have the right scopes.
        # Therefore, we could leave off the integration-related key/value pairs in this call.
        # However, that would count against our linter, so for completeness, we are adding them.
        forbid: access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true),
        enforce_oauth_app_policy: repo.private?,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      authorize_content(:delete, issue: comment.try(:issue), repo: repo)

      comment.destroy

      # Metric to see how many unverified users make this request over a period of time.
      # https://github.com/github/github/pull/94198#issuecomment-410690200
      tags = []
      tags << "type:deleting_comment_using_unverified_email" if current_user.must_verify_email?
      GitHub.dogstats.increment("api.routes.repositories_repository_id_issues_comments_comment_id", tags: tags)
    end

    deliver_empty(status: 204)
  end

  def resolve_tenant_from_repo
    repo = find_repo!
    Business.find_by(id: repo.tenant_id)
  end

  private

  def preload_comments_edits?(options)
    params   = options[:mime_params]
    params.include?(:html) || params.include?(:full) || params.include?(:text)
  end

  def filter_scope(scope)
    if (since = time_param!(:since)).present?
      scope.since(since.getlocal)
    else
      scope
    end
  end

  def filter_and_sort(scope)
    sort = params[:sort] || "id"
    direction = params[:direction] || "asc"
    scope = scope.sorted_by(sort, direction)
    filter_scope(scope)
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :issue_comment, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def get_comments(repo, issues_read, pull_requests_read)
    joins_scope = IssueComment.where(repository: repo).joins(:issue)
    scope = joins_scope.where(issues: { user_hidden: false })
    scope = scope.or(joins_scope.where(issues: { user_id: current_user }))
    scope = if issues_read && pull_requests_read
      repo.has_issues? ? scope.with_issue : scope.with_pull_request
    elsif issues_read && !pull_requests_read
      repo.has_issues? ? scope.without_pull_request : deliver_error!(404)
    elsif pull_requests_read
      scope.with_pull_request
    else
      nil
    end

    return [] if scope.nil?

    scope = scope.filter_spam_for(current_user).
      includes(:issue).
      preload([:performed_via_integration, :user])
    comments = paginate_rel(filter_and_sort(scope))
    comments.to_a
  end
end
