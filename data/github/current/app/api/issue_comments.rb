# typed: true
# frozen_string_literal: true

class Api::IssueComments < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Api::Issues::Limits
  include Api::App::UsersDependency
  include Api::App::DatabaseConnectionHelper
  include Api::App::CommentEditRestrictionDependency
  include Api::App::Mysql1ReplicaAuth
  include Api::DatabaseResourceUpdateRateLimiting

  # Get Comments for a Repo
  get "/repositories/:repository_id/issues/comments", operation_id: "issues/list-comments-for-repo" do
    replica_clusters = T.let([ApplicationRecord::Collab], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
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

      options = Api::SerializerOptions.fill(default_options)
      comments = get_comments(repo, issues_read, pull_requests_read)

      GitHub.dogstats.distribution_time "api.prefill", tags: ["action:repository_comments_list"] do
        prefill_comments(comments, current_user, repo, options)
      end

      GitHub.dogstats.distribution_time "api.deliver", tags: ["action:repository_comments_list"] do
        deliver(:issue_comment_hash, comments, repo: repo)
      end
    end
  end

  # Get Comments for an Issue
  get "/repositories/:repository_id/issues/:issue_number/comments", operation_id: "issues/list-comments", resolve_tenant_context: :resolve_tenant_from_repo do
    replica_clusters = T.let([ApplicationRecord::Collab], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo = find_repo!
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
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

      options = Api::SerializerOptions.fill(default_options)

      GitHub.dogstats.distribution_time "api.prefill", tags: ["action:issue_comments_list"] do
        prefill_comments(comments, current_user, repo, options)
      end

      GitHub.dogstats.distribution_time "api.deliver", tags: ["action:issue_comments_list"] do
        deliver(:issue_comment_hash, comments, repo: repo)
      end
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
      $includePerformedViaGitHubApp: Boolean!,
    ) {
      addComment(input: {
        subjectId: $issueId,
        body: $body,
        clientMutationId: $clientMutationId
      }) {
        commentEdge {
          comment: node {
            databaseId
            ...Api::Serializer::IssuesDependency::IssueCommentFragment
          }
        }
      }
    }
  GRAPHQL

  # Create a Comment for an Issue
  post "/repositories/:repository_id/issues/:issue_number/comments", operation_id: "issues/create-comment", resolve_tenant_context: :resolve_tenant_from_repo do
    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo  = find_repo!
      issue = Issues.domain.by_number(int_id_param!(key: :issue_number), repo_id: repo.id).ok
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
      ensure_issues_enabled_or_pr!(repo, issue)

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
          if FeatureFlag.vexi.enabled_or_raise?(:issue_comment_api_rate_limit_logging, repo) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            log_rate_limited_request
          end

          unless GitHub.enterprise?
            @meta ||= {}
            @meta[GitHub::Limiters::Middleware::HEADER_SECONDARY_RATE_LIMITED] = "true"
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

      if current_user&.feature_flag_enabled_or_raise?(:may_post_comment_actions) && issue.pull_request? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        CommentAction.safe_upsert(
          repository: repo,
          comment_type: "IssueComment",
          comment_id: comment.database_id,
          actions: data["actions"],
        )
      end

      deliver :graphql_issue_comment_hash, comment, status: 201
    end
  end

  ShowIssueCommentQuery = PlatformClient.parse <<-'GRAPHQL'
    query(
      $id:ID!,
      $includeBody:Boolean!,
      $includeBodyHTML:Boolean!,
      $includeBodyText:Boolean!,
      $includePerformedViaGitHubApp: Boolean!,
    ) {
      comment: node(id:$id) {
        ...Api::Serializer::IssuesDependency::IssueCommentFragment
      }
    }
  GRAPHQL

  # View a single Issue Comment
  get "/repositories/:repository_id/issues/comments/:comment_id", operation_id: "issues/get-comment" do
    replica_clusters = T.let([ApplicationRecord::Collab], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
      elsif issue.pull_request? && !repo.has_pull_requests?
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
  end

  verbs :patch, :post, "/repositories/:repository_id/issues/comments/:comment_id", operation_id: "issues/update-comment" do
    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
      ensure_issues_enabled_or_pr!(repo, issue)

      ensure_comment_edit_allowed!(repo: repo, resource: comment, issue: issue)

      check_database_resource_update_rate_limit!(resource: comment, repo: repo, current_user: current_user)

      data = receive_with_schema("issue-comment", "update-legacy")

      if Issues::Comments.update_comment(comment, data["body"], current_user, performed_via_integration: current_integration)
        if current_user&.feature_flag_enabled_or_raise?(:may_post_comment_actions) && issue.pull_request? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          CommentAction.safe_upsert(
            repository: repo,
            comment_type: "IssueComment",
            comment_id: T.must(comment.id),
            actions: data["actions"],
          )
        end
        deliver :issue_comment_hash, comment, repo: repo
      else
        deliver_error 422,
          errors: comment.errors,
          documentation_url: @documentation_url
      end
    end
  end

  verbs :put, :post, "/repositories/:repository_id/issues/comments/:comment_id/pin", operation_id: "issues/pin-comment", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      repo = find_repo!

      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      set_context_controller_action(issue, "pin-comment")

      control_access :pin_issue_comment,
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
      ensure_issues_enabled_or_pr!(repo, issue)
      check_database_resource_update_rate_limit!(resource: comment, repo: repo, current_user: current_user)

      result = Issues.domain.comments.pin(issue_comment: comment, actor: current_user)
      case result
      when GH::Result::Ok
        pinned_issue_comment = T.cast(result.ok, PinnedIssueComment)
        issue_comment = T.cast(pinned_issue_comment.issue_comment, IssueComment)

        deliver :issue_comment_hash, issue_comment, repo: repo
      when GH::Result::Error::Validation
        deliver_error 422,
          errors: result.model.errors,
          documentation_url: @documentation_url
      when GH::Result::Error
        deliver_error 503,
          message: "Encountered an error while pinning the issue comment",
          documentation_url: @documentation_url
      end
    end
  end

  delete "/repositories/:repository_id/issues/comments/:comment_id/pin", operation_id: "issues/unpin-comment", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      repo = find_repo!

      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      set_context_controller_action(issue, "unpin-comment")

      control_access :pin_issue_comment,
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
      ensure_issues_enabled_or_pr!(repo, issue)
      check_database_resource_update_rate_limit!(resource: comment, repo: repo, current_user: current_user)

      result = Issues.domain.comments.unpin(issue_comment: comment, actor: current_user)
      case result
      when GH::Result::Ok
        deliver_empty(status: 204)
      when GH::Result::Error::NotFound
        deliver_error!(404)
      when GH::Result::Error
        deliver_error 503,
          message: "Encountered an error while unpinning the issue comment",
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

    replica_clusters = T.let([ApplicationRecord::Repositories, ApplicationRecord::IamAbilities, ApplicationRecord::Collab, ApplicationRecord::Mysql1], T::Array[T.class_of(ApplicationRecord::Base)])
    with_replica_clusters(replica_clusters) do
      repo    = find_repo!
      comment = record_or_404 IssueComments::Public.by_id(int_id_param!(key: :comment_id), repository_id: repo.id)
      issue   = record_or_404 comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
      ensure_issues_enabled_or_pr!(repo, issue)

      ensure_comment_edit_allowed!(repo: repo, resource: comment, issue: issue)

      Issues::Comments.delete(comment, current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

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

  # Avoids OR conditions for non-spammy users to allow MySQL to use indexes efficiently.
  # See: https://github.com/github/mysql-database-usage/issues/3025
  def get_comments(repo, issues_read, pull_requests_read)
    # Optimize spam filtering to avoid OR conditions when possible.
    # OR conditions prevent MySQL from using indexes efficiently.
    #
    # For non-spammy users (the common case), we can simplify:
    # - Their own content won't be spam-hidden, so we don't need "OR user_id = viewer"
    # - Just filter on user_hidden = false (no OR needed)

    joins_scope = IssueComment.select("issue_comments.id").where(repository: repo).joins(:issue)

    # Optimize issue-level spam filtering
    # If the viewer is not spammy, their issues won't be hidden, so skip the OR
    viewer_is_spammy = current_user&.spammy?
    if current_user.nil?
      # Anonymous: match legacy behavior (OR user_id IS NULL)
      scope = joins_scope.where(issues: { user_hidden: false })
        .or(joins_scope.where(issues: { user_id: nil }))
    elsif !viewer_is_spammy
      scope = joins_scope.where(issues: { user_hidden: false })
    else
      # Spammy users need to see their own hidden issues
      scope = joins_scope.where(issues: { user_hidden: false })
        .or(joins_scope.where(issues: { user_id: current_user.id }))
    end

    has_issues = repo.has_issues?
    has_prs = repo.has_pull_requests?

    scope = if issues_read && pull_requests_read
      if has_issues && has_prs
        scope.with_issue
      elsif has_issues
        scope.without_pull_request
      elsif has_prs
        scope.with_pull_request
      else
        deliver_error!(404)
      end
    elsif issues_read && !pull_requests_read
      has_issues ? scope.without_pull_request : deliver_error!(404)
    elsif pull_requests_read
      has_prs ? scope.with_pull_request : deliver_error!(404)
    else
      nil
    end

    return [] if scope.nil?

    # Use skip_user_filter_if_not_spammy to avoid OR for non-spammy users
    scope = scope.filter_spam_for(current_user, skip_user_filter_if_not_spammy: true)

    comments = paginate_rel(filter_and_sort(scope)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    comments_joins_scope = IssueComment.where(repository: repo).joins(:issue).where(id: comments.ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    comments_joins_scope = comments_joins_scope.includes(:issue).preload([:performed_via_integration, :user])

    paginator.collection_size = comments.total_entries

    filter_and_sort(comments_joins_scope).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def prefill_comments(comments, current_user, repo, options)
    IssueComment.prefill_associations(comments, preload_comment_edits: preload_comments_edits?(options), current_user: current_user, repository: repo)
  end
end
