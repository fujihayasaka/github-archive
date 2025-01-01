# typed: true
# frozen_string_literal: true

class Api::GistComments < Api::App
  include ReceiveSchemaWithOpenApi

  include Api::App::UsersDependency

  # list all comments on a gist
  get "/gists/:gist_id/comments", operation_id: "gists/list-comments" do
    control_access :list_gist_comments, resource: gist, allow_integrations: false, allow_user_via_granular_actor: true

    comments = if gist.comment_moderation_enabled? && !gist.comments_enabled?
      GistComment.none
    else
      gist.comments.order(created_at: :asc)
    end
    comments = paginate_rel(comments)
    GitHub::PrefillAssociations.prefill_associations(comments, [:user, :gist, { latest_user_content_edit: :editor }], available_records: [gist])

    deliver :gist_comment_hash, comments
  end

  # get a gist comment
  get "/gists/:gist_id/comments/:comment_id", operation_id: "gists/get-comment" do
    comment = gist.comments.find_by_id(params[:comment_id])
    control_access :get_gist_comment, resource: comment, allow_integrations: false, allow_user_via_granular_actor: true
    deliver :gist_comment_hash, comment, last_modified: calc_last_modified_for_object(comment)
  end

  # create a gist comment
  post "/gists/:gist_id/comments", operation_id: "gists/create-comment" do
    control_access :create_gist_comment, resource: gist, allow_integrations: false, allow_user_via_granular_actor: true, challenge: true
    ensure_not_blocked! current_user, gist.user_id

    # Introducing strict validation of the gist-comment.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_openapi(skip_validation: true)

    comment = gist.comments.build \
      body: data["body"]
    comment.user = current_user

    if comment.save
      GitHub.dogstats.increment("comment", tags: ["action:create", "subject:gist", "via:api", "visibility:#{gist.visibility}", "ownership:#{gist.ownership}"])

      deliver :gist_comment_hash, comment, status: 201
    else
      deliver_error 422,
        errors: comment.errors,
        documentation_url: @documentation_url
    end
  end

  # update a gist comment
  verbs :patch, :post, "/gists/:gist_id/comments/:comment_id", operation_id: "gists/update-comment" do
    comment = gist.comments.find_by_id(params[:comment_id])
    control_access :update_gist_comment, resource: comment, allow_integrations: false, allow_user_via_granular_actor: true, challenge: true

    data = receive_with_openapi
    comment.update_body(data["body"], current_user)

    deliver :gist_comment_hash, comment
  end

  # delete a gist comment
  delete "/gists/:gist_id/comments/:comment_id", operation_id: "gists/delete-comment" do
    receive_with_openapi

    comment = gist.comments.find_by_id(params[:comment_id])
    control_access :delete_gist_comment, resource: comment, allow_integrations: false, allow_user_via_granular_actor: true, challenge: true

    comment.delete

    deliver_empty status: 204
  end

  # Enterprise Managed Users are not allowed to create Gists
  # Only write operations will reach this stage
  def emu_ownership_satisfied(resource:, target_provider:)
    :no
  end

  private

  def gist
    @gist ||= find_gist!(param_name: :gist_id)
  end
end
