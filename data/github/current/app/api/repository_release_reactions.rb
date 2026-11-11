# typed: true
# frozen_string_literal: true

class Api::RepositoryReleaseReactions < Api::App
  include ReceiveSchemaWithOpenApi

  # List Reactions for this Release
  get "/repositories/:repository_id/releases/:release_id/reactions", operation_id: "reactions/list-for-release" do
    repo = find_repo!
    release = Releases::Public.load_release(int_id_param!(key: :release_id))

    record_or_404(release)
    control_access :get_release, repo: repo, resource: release, allow_integrations: true, allow_user_via_granular_actor: true

    scope = T.unsafe(release).reactions.not_spammy.reorder("id ASC")
    if (filter = params[:content].presence) && (emotion = Emotion.find_by_label(filter.downcase))
      scope = scope.where(content: emotion.content)
    end

    reactions = paginate_rel(scope)
    GitHub::PrefillAssociations.prefill_associations(reactions, :user)

    deliver :reaction_hash, reactions
  end

  # Create Reaction for this Release
  post "/repositories/:repository_id/releases/:release_id/reactions",  operation_id: "reactions/create-for-release" do
    repo = find_repo!
    release = Releases::Public.load_release(int_id_param!(key: :release_id))

    record_or_404(release)
    deliver_error!(404) unless T.unsafe(release).repository_id == repo.id

    control_access :create_release_reaction, repo: repo, resource: release, allow_integrations: true, allow_user_via_granular_actor: true
    data = receive_with_schema("reaction", "create-for-release")

    reaction = Reaction.react user: current_user,
      subject_id: T.must(release).id,
      subject_type: release.class.name,
      content: Emotion.find_by_label(data["content"]).content

    deliver!(:reaction_hash, reaction, status: 200) if reaction.exists?
    deliver!(:reaction_hash, reaction, status: 201) if reaction.created?

    deliver_error!(422, errors: reaction.errors)
  end

  # Delete Reaction for this release
  delete "/repositories/:repository_id/releases/:release_id/reactions/:reaction_id", operation_id: "reactions/delete-for-release"  do
    repo = find_repo!
    release = Releases::Public.load_release(int_id_param!(key: :release_id))
    record_or_404(release)
    deliver_error!(404) unless T.unsafe(release).repository_id == repo.id

    receive_with_schema("reaction", "delete")
    reaction = T.unsafe(release).reactions.find_by(id: int_id_param!(key: :reaction_id))
    record_or_404(reaction)

    control_access(
      :delete_reaction,
      reaction: reaction,
      resource: release,
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
