# typed: true
# frozen_string_literal: true

class Api::PullComments < Api::App
  include ReceiveSchemaWithOpenApi
  include Scientist

  # List all review comments for a repo
  get "/repositories/:repository_id/pulls/comments", operation_id: "pulls/list-review-comments-for-repo" do
    repo = find_repo!
    control_access :list_pull_requests,
      repo: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    review_comments =
      if repo.feature_enabled?(:pulls_comments_optimized_query)
        candidate_pull_review_comments(repo)
      else
        original_pull_review_comments(repo)
      end

    if repo.feature_enabled?(:pulls_comments_optimized_query)
      review_comments = review_comments.select { |review_comment| review_comment.pull_request.present? }
    end

    GitHub.dogstats.time "prefill", tags: ["via:api", "action:pulls_comments_list"] do
      PullRequestReviewComment.prefill_associations(review_comments)
      Reaction::Summary.prefill(review_comments)

      deliver :pull_request_review_comment_hash, review_comments, repo: repo
    end
  end

  # List comments for a pull request review comments
  #
  # NOTE:
  # - Issue comments can be retrieved via Issues API.
  # - Commit comments can be retrieved via Commits API.
  get "/repositories/:repository_id/pulls/:pull_number/comments", operation_id: "pulls/list-review-comments" do
    repo, issue, pull = find_repo_and_pull_request
    control_access :list_pull_request_comments,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    scope = pull.review_comments.filter_spam_for(current_user)
    scope = filter_and_sort(scope)
    # Remove pending review comments.
    scope = scope.with_submitted_state
    review_comments = paginate_rel(scope)

    PullRequestReviewComment.prefill_associations(review_comments, issue: issue)
    Promise.all(
      review_comments.map do |review_comment|
        CommentAuthorAssociation.new(comment: review_comment, viewer: current_user).async_to_sym.then do |sym|
          review_comment.preload_attr(:author_association_symbol, sym.to_s.upcase)
        end
      end
    ).sync
    GitHub::PrefillAssociations.prefill_associations(review_comments.map(&:pull_request_review_thread), :pull_request, available_records: [pull])
    Reaction::Summary.prefill(review_comments)

    deliver :pull_request_review_comment_hash, review_comments, repo: repo
  end

  # Share behavior between optional "in_reply_to" data key and new param.
  #
  # repo - The repository for this PR
  # pull - The pull request
  # rel - String that describes which part of the schema we should use (create-legacy or create-reply)
  def create_pull_request_review_comment(repo, pull, rel)
    data = receive_with_schema("pull-request-review-comment", rel)

    end_commit_oid = data["commit_id"] || pull.head_sha

    pull_comparison = PullRequest::Comparison.find(
      pull: pull,
      start_commit_oid: pull.merge_base,
      end_commit_oid: end_commit_oid,
      base_commit_oid: pull.merge_base,
    )

    unless pull_comparison
      deliver_error!(422, {
        errors: [
          api_error(:PullRequestReviewComment, :commit_id, :invalid, {
            message: "commit_id is not part of the pull request",
          }),
        ],
        documentation_url: @documentation_url,
      })
    end

    if changeset_active?(:remove_diff_relative_comment_fields) && data.has_key?("position")
      errors = []
      errors << "position is not supported for creating comments. Use line and side instead."
      deliver_error!(422, {
        errors: errors,
        documentation_url: @documentation_url,
      })
    end

    merge_base_sha = pull.find_best_merge_base_sha(head_sha: end_commit_oid)
    review = pull.reviews.build(user: current_user, head_sha: end_commit_oid, merge_base_sha: merge_base_sha)

    GitHub.logger.info(
      "code.namespace": "Api::PullComments",
      "code.function": "create_pull_request_review_comment",
      "gh.actor.id": current_user&.id,
      "gh.integration.id": current_integration&.id,
      "gh.pull_request.review_comments.position": !!data["position"],
      "gh.pull_request.review_comments.start_side": !!data["start_side"],
      "gh.pull_request.review_comments.start_line": !!data["start_line"],
      "gh.pull_request.review_comments.line": !!data["line"],
    )

    if (parent = yield pull, data).blank?
      subject_type = data["subject_type"] || "line"
      if data.has_key?("line") || subject_type == "file"
        thread = review.build_thread(subject_type: subject_type)

        attributes = {
          user: current_user,
          diff: pull_comparison.diffs,
          body: data["body"],
          path: data["path"],
          line: data["line"],
          side: data["side"]&.downcase&.to_sym || :right
        }

        if data.has_key?("start_line")
          attributes.merge!(
            start_line: data["start_line"],
            start_side: data["start_side"]&.downcase&.to_sym || :right
          )
        end

        comment = thread.build_first_comment(**attributes)
      else
        thread, comment = review.build_thread_with_comment(
          user: current_user,
          body: data["body"],
          diff: pull_comparison.diffs,
          position: data["position"].to_i,
          position_is_used: !!data["position"],
          path: data["path"],
        )
      end
    else
      thread = parent.pull_request_review_thread
      comment = thread.build_reply(
        pull_request_review: review,
        user: current_user,
        body: data["body"]
      )
    end

    PullRequestReview.transaction do
      raise ActiveRecord::Rollback unless review.save && thread.save && comment.save
      review.comment!
    end

    if comment.new_record?
      errors = []
      errors.concat(convert_error(comment.errors)) if comment
      errors.concat(convert_error(thread.errors)) if thread && errors.empty?
      errors.concat(convert_error(review.errors)) if review && errors.empty?

      deliver_error(422, {
        errors: errors,
        documentation_url: @documentation_url,
      })
    else
      deliver :pull_request_review_comment_hash, comment, status: 201, repo: repo
    end
  end

  # Create a new pull request review comment
  post "/repositories/:repository_id/pulls/:pull_number/comments", operation_id: "pulls/create-review-comment" do
    repo, _issue, pull = find_repo_and_pull_request

    control_access :create_pull_request_comment,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    authorize_content :update, repo: repo

    rel = "create-legacy"

    create_pull_request_review_comment(repo, pull, rel) do |pull, data|
      ensure_data_satisfies_schema!(data, "pull-request-review-comment", rel)
      next unless data["in_reply_to"].present?

      parent = pull.review_comments.find_by_id(data["in_reply_to"])

      unless parent
        deliver_error!(422, {
          errors: [api_error(:PullRequestReviewComment, :in_reply_to, :invalid)],
          documentation_url: @documentation_url,
        })
      end

      parent
    end
  end

  # Create a new pull request review comment
  post "/repositories/:repository_id/pulls/:pull_number/comments/:in_reply_to_id/replies", operation_id: "pulls/create-reply-for-review-comment" do
    repo, _issue, pull = find_repo_and_pull_request

    control_access :create_pull_request_comment,
      repo: repo,
      resource: pull,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    authorize_content :update, repo: repo

    create_pull_request_review_comment(repo, pull, "create-reply") do |pull, data|
      ensure_data_satisfies_schema!(data, "pull-request-review-comment", "create-reply")
      in_reply_to = int_id_param!(key: :in_reply_to_id)

      parent = pull.review_comments.find_by_id(in_reply_to)

      unless parent
        deliver_error!(404, {
          message: "Parent comment not found",
          documentation_url: @documentation_url,
        })
      end

      parent
    end
  end

  # Get a single pull request review comment
  get "/repositories/:repository_id/pulls/comments/:comment_id", operation_id: "pulls/get-review-comment" do
    repo, comment = find_repo_and_pull_request_comment

    control_access :get_pull_request_comment,
      repo: repo,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    Reaction::Summary.prefill([comment])

    deliver :pull_request_review_comment_hash, comment,
      repo: repo, last_modified: calc_last_modified_for_object(comment)
  end

  # Update a pull request review comment
  verbs :patch, :post, "/repositories/:repository_id/pulls/comments/:comment_id", operation_id: "pulls/update-review-comment" do
    repo, comment = find_repo_and_pull_request_comment

    control_access :update_pull_request_comment,
      repo: repo,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    authorize_content :update, repo: repo

    data = receive_with_schema("comment", "update-for-pull")

    if comment.update_body(data["body"], current_user)
      Reaction::Summary.prefill([comment])
      deliver :pull_request_review_comment_hash, comment, repo: repo
    else
      deliver_error 422,
        errors: comment.errors,
        documentation_url: @documentation_url
    end
  end

  delete "/repositories/:repository_id/pulls/comments/:comment_id", operation_id: "pulls/delete-review-comment" do
    # Introducing strict validation of the comment.delete-for-pull
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("comment", "delete-for-pull", skip_validation: true)

    repo = find_repo!
    comment = repo.pull_request_review_comments.find_by_id(int_id_param!(key: :comment_id))

    deliver_error!(404) unless comment
    deliver_error!(404) if comment.hide_from_user?(current_user)

    control_access :delete_pull_request_comment,
      repo: repo,
      resource: comment,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    if comment.destroy
      deliver_empty(status: 204)
    else
      deliver_error 422,
        errors: comment.errors,
        documentation_url: @documentation_url
    end
  end

  private

  def find_repo_and_pull_request
    repo = find_repo!
    issue = repo.issues.find_by_number(int_id_param!(key: :pull_number)) if repo
    pull = issue.pull_request if issue

    deliver_error!(404) if pull && pull.hide_from_user?(current_user)

    [repo, issue, pull]
  end

  def find_repo_and_pull_request_comment
    repo = find_repo!
    comment = repo.pull_request_review_comments.find_by_id(int_id_param!(key: :comment_id))
    deliver_error!(404) unless comment
    deliver_error!(404) if comment.hide_from_user?(current_user)
    deliver_error!(404) if comment.pending?

    [repo, comment]
  end

  def filter_and_sort(scope)
    # filter by updated_at
    if (since = params[:since]).present?
      since = parse_time!(since).getlocal
      scope = scope.since(since)
    end

    if (sort = params[:sort]).present?
      direction = params[:direction] || "asc"
      scope = scope.sorted_by sort, direction
    else
      scope = scope.sorted_by "id", "asc"
    end

    scope
  end

  def original_pull_review_comments(repo)
    scope = repo.pull_request_review_comments
    scope = scope.preload(:pull_request_review_thread, :pull_request)
    scope = scope.filter_spam_for(current_user)
    scope = filter_and_sort(scope)
    # Remove pending review comments.
    scope = scope.with_submitted_state
    paginate_rel(scope)
  end

  def candidate_pull_review_comments(repo)
    scope = repo.pull_request_review_comments
    scope = scope.select(:id)
    scope = scope.filter_spam_for(current_user)
    scope = filter_and_sort(scope)
    # Remove pending review comments.
    scope = scope.with_submitted_state

    scope = paginate_rel(scope)
    paginator.collection_size = scope.total_entries

    review_comments_ids = scope.pluck(:id)
    filter_and_sort(repo.pull_request_review_comments.where(id: review_comments_ids).includes(:pull_request_review_thread, :pull_request))
  end

  def paginated_ids(relation)
    paginate_rel(relation.scoped(select: "#{relation.quoted_table_name}.id")).map(&:id)
  end

  def authorize_content(operation = :create, data = {})
    authorization = ContentAuthorizer.authorize(current_user, :pull_request_comment, operation, data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end
end
