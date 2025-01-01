# typed: strict
# frozen_string_literal: true

class Api::GitTags < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::GitActorHelpers

  # Get the contents of a tag object
  get "/repositories/:repository_id/git/tags/:tag_id", operation_id: "git/get-tag" do
    control_access :get_tag,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)

    sha = params[:tag_id]
    begin
      tag = repo.objects.read(sha, "tag")
    rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId
      deliver_error!(404)
    end
    deliver :tag_hash, tag, repo: repo, last_modified: calc_last_modified_for_object(repo)
  end

  # Create a new tag object
  post "/repositories/:repository_id/git/tags", operation_id: "git/create-tag" do
    control_access :create_tag,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_repo_content!(repo)
    ensure_repo_writable!(repo)

    data = receive_with_schema("git-tag", "create-legacy")
    data = attr(data, :object, :tag, :message, :tagger)
    sha_param!(:object, data)

    tagger = if data[:tagger]
      actor = git_actor!(data, key: :tagger, default_time: Time.zone.now)
      actor.to_gitrpc_hash.symbolize_keys
    else
      {
        name: current_user.git_author_name,
        email: current_user.git_author_email,
        time: Time.zone.now,
      }
    end

    unless ::Git::Ref.well_formed?(data[:tag])
      deliver_error!(422, message: "Could not verify tag name")
    end

    begin
      repo.check_custom_hooks(GitHub::NULL_OID, data[:object], "refs/tags/#{data[:tag]}",
        reflog_data: request_reflog_data("tag create api"))
      oid = repo.rpc.create_tag_annotation(data[:tag], data[:object], message: data[:message], tagger: tagger)
    rescue Git::Ref::HookFailed => e
      deliver_error!(422, message: "Could not create tag because a Git pre-receive hook failed.\n\n#{e.message}")
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing => e
      deliver_error!(422, message: "Could not verify object")
    rescue GitRPC::Failure => e
      raise unless [Rugged::OdbError, Rugged::ReferenceError].any? { |err| e.original.is_a? err }
      deliver_error!(422, message: "Could not verify object")
    end

    obj = repo.objects.read(oid, "tag")
    deliver :tag_hash, obj, repo: repo, status: 201
  end
end
