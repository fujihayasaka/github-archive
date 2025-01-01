# typed: true
# frozen_string_literal: true

class Api::RepositoryCommitComments < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::DatabaseResourceUpdateRateLimiting

  # List commit comments for a repository
  get "/repositories/:repository_id/comments", operation_id: "repos/list-commit-comments-for-repo" do
    control_access :list_commit_comments,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # This query uses an unusual JOIN to improve performance.
    # Selecting only the `id` allows MySQL to only read from an index,
    # which is much faster that using the index and the table.
    # We then `JOIN` the table to this result set to load the full
    # records by primary key.
    #
    # Also, we're going to be ordering by id, which makes MySQL try to use the
    # primary index for the entire lookup. This is *extremely* slow for
    # repositories with a lot of commit comments, so we tell MySQL to ignore
    # the primary index for the ORDER BY clause in order to give it a chance to
    # use a better index.
    comment_ids = repo.commit_comments
      .select(:id)
      .from("`commit_comments` IGNORE INDEX FOR ORDER BY (PRIMARY)")
      .filter_spam_for(current_user)
      .order("id asc")
    comment_ids = paginate_rel(comment_ids)

    comments = repo.commit_comments.joins(Arel.sql(<<-SQL)).order("id asc")
      INNER JOIN (#{comment_ids.to_sql}) AS ids on commit_comments.id = ids.id
    SQL

    # We've already applied pagination to the IDs, so `comments` will always
    # be a single page of results, but we need to call `#paginate` again here
    # so that the `WillPaginate` methods are available and we can set
    # `total_entries`.
    comments = comments.paginate(page: 1, per_page: pagination[:per_page])
    comments.total_entries = comment_ids.total_entries

    GitHub.dogstats.time "prefill", tags: ["via:api", "action:repos_comments_list"] do
      GitHub::PrefillAssociations.prefill_associations(comments, [{ latest_user_content_edit: :editor }, { user: :profile }])
      Reaction::Summary.prefill(comments)

      deliver :commit_comment_hash, comments, repo: repo
    end
  end

  # List commit comments for a single commit
  get "/repositories/:repository_id/commits/*/comments", operation_id: "repos/list-comments-for-commit" do
    ref = params[:splat].first
    control_access :list_commit_comments,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    commit =
      if ref.size == 40 && ref =~ /^[A-Za-z0-9]{40}$/n
        ref
      else
        find_commit!(repo, ref, @documentation_url)
      end
    comments = paginate_rel(repo.commit_comments.filter_spam_for(current_user).order("id asc").where(commit_id: commit.to_s))
    GitHub::PrefillAssociations.prefill_associations(comments, [{ latest_user_content_edit: :editor }, { user: :profile }])
    Reaction::Summary.prefill(comments)
    deliver :commit_comment_hash, comments, repo: repo
  end

  # Create a commit comment
  post "/repositories/:repository_id/comments", operation_id: :deprecated do
    @route_owner = "@github/repos"
    control_access :create_commit_comment,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(repo: repo, operation: :create)

    data = receive_with_schema("comment", "deprecated-create")
    attributes = attr(data, :path, :position, :line, :commit_id, :body)
    attributes.update user: current_user, repository: repo

    comment = CommitComment.new(attributes)
    if comment.save
      deliver :commit_comment_hash, comment, status: 201, repo: repo
    else
      deliver_error 422, errors: comment.errors, documentation_url: @documentation_url
    end
  end

  # Create a commit comment
  post "/repositories/:repository_id/commits/*/comments", operation_id: "repos/create-commit-comment" do
    ref = params[:splat].first
    control_access :create_commit_comment,
      repo: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(repo: repo, operation: :create)

    commit = find_commit!(repo, ref, @documentation_url)

    data = receive_with_schema("comment", "create-legacy")
    attributes = attr(data, :path, :position, :line, :commit_id, :body)
    attributes.update user: current_user, repository: repo

    attributes[:commit_id] = commit.oid if commit.oid

    comment = CommitComment.new(attributes)
    comment.modifying_user = current_user
    if comment.save
      deliver :commit_comment_hash, comment, status: 201, repo: repo
    else
      deliver_error 422, errors: comment.errors, documentation_url: @documentation_url
    end
  end

  # Get a commit comment
  get "/repositories/:repository_id/comments/:comment_id", operation_id: "repos/get-commit-comment" do
    repo = find_repo!
    comment = find_comment(repo)
    control_access :get_commit_comment,
      repo: repo,
      comment: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    Reaction::Summary.prefill([comment])
    deliver :commit_comment_hash, comment, repo: repo, last_modified: calc_last_modified_for_object(comment)
  end

  # Update a commit comment
  verbs :patch, :post, "/repositories/:repository_id/comments/:comment_id", operation_id: "repos/update-commit-comment" do
    repo = find_repo!
    comment = find_comment(repo)
    control_access :update_commit_comment,
      repo: repo,
      comment: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(repo: repo, operation: :update)

    check_database_resource_update_rate_limit!(resource: comment, repo: repo, current_user: current_user)

    data = receive_with_schema("comment", "update-for-commit-legacy")

    # ensure the modifying_user is set with the current_user so permissions are checked correctly for bot users.
    comment.modifying_user = current_user
    if comment.update_body(data["body"], current_user)
      deliver :commit_comment_hash, comment, repo: repo
    else
      deliver_error 422,
        errors: comment.errors,
        documentation_url: @documentation_url
    end
  end

  # Delete a commit comment
  delete "/repositories/:repository_id/comments/:comment_id", operation_id: "repos/delete-commit-comment" do
    # Introducing strict validation of the comment.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("comment", "delete", skip_validation: true)

    repo = find_repo!
    comment = find_comment(repo)
    control_access :delete_commit_comment,
      repo: repo,
      comment: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorize_content(repo: repo, operation: :delete)

    comment.destroy
    deliver_empty(status: 204)
  end

  private

  def find_comment(repo)
    return nil if !repo
    comment = repo.commit_comments.find_by_id(int_id_param!(key: :comment_id))

    if comment && comment.hide_from_user?(current_user)
      deliver_error!(404)
    else
      comment
    end
  end

  def authorize_content(repo:, operation: :create)
    authorization = ContentAuthorizer.authorize(current_user, :commit_comment, operation, repo: repo)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

end
