# typed: true
# frozen_string_literal: true

class Api::RepositoryCommitCommentReactions < Api::App
  include ReceiveSchemaWithOpenApi

  # List Reactions for this Commit Comment
  get "/repositories/:repository_id/comments/:comment_id/reactions", operation_id: "reactions/list-for-commit-comment" do
    repo = find_repo!
    comment = repo.commit_comments.find_by_id(int_id_param!(key: :comment_id))

    control_access :get_commit_comment,
      repo: repo,
      comment: comment,
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

  # Create Reaction for this Commit Comment
  post "/repositories/:repository_id/comments/:comment_id/reactions", operation_id: "reactions/create-for-commit-comment" do
    repo = find_repo!
    comment = repo.commit_comments.find_by_id(int_id_param!(key: :comment_id))

    if repo.public?
      set_forbidden_message "Insufficient scopes for reacting to this Commit Comment."
    end

    control_access :create_commit_comment_reaction,
      resource: comment,
      repo: repo,
      challenge: repo.public?,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: repo.private?

    authorize_content :commit_comment, repo: repo
    ensure_content_visible comment

    data = receive_with_schema("reaction", "create-for-commit-comment-legacy")
    reaction = Reaction.react user: current_user,
      subject_id: comment.id,
      subject_type: comment.class.name,
      content: Emotion.find_by_label(data["content"]).content

    deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
    deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

    deliver_error!(422, errors: reaction.errors)
  end

  delete "/repositories/:repository_id/comments/:comment_id/reactions/:reaction_id", operation_id: "reactions/delete-for-commit-comment" do
    repo    = find_repo!
    comment = repo.commit_comments.find_by_id(int_id_param!(key: :comment_id))
    record_or_404(comment)

    receive_with_schema("reaction", "delete")
    reaction = comment.reactions.find_by(id: int_id_param!(key: :reaction_id))
    record_or_404(reaction)

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

  private

  def authorize_content(kind, data = {})
    authorization = ContentAuthorizer.authorize(current_user, kind, "update", data)
    deliver_content_authorization_denied!(authorization) if authorization.failed?
  end

  def ensure_content_visible(content)
    deliver_error!(404) if content.nil? || content.hide_from_user?(current_user)
  end
end
