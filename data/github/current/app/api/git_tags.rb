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
      oid = if repo.feature_enabled?(:create_tag_spokes)
        repo.spokes_api.with_transaction do
          repo.spokes_api.create_tag(name: data[:tag], target: data[:object], message: data[:message], tagger: sanitize_tagger(tagger))
        end
      else
        science "create_tag_spokes_experiment" do |e|
          e.context({ repository: repo.id, data:, tagger: })
          e.use { repo.rpc.create_tag_annotation(data[:tag], data[:object], message: data[:message], tagger: tagger) }
          e.try do
            repo.spokes_api.with_transaction do
              repo.spokes_api.create_tag(name: data[:tag], target: data[:object], message: data[:message], tagger: sanitize_tagger(tagger))
            end
          end
          e.compare_errors do |control, candidate|
            # All of these errors are rescued identically, so we can ignore
            # differences between them in the control and candidate.
            if [GitRPC::ObjectMissing, GitRPC::InvalidObject].include?(control.class) && candidate.is_a?(SpokesAPI::NotFound)
              true
            else
              control.class == candidate.class && control.message == candidate.message
            end
          end
        end
      end
    rescue Git::Ref::HookFailed => e
      deliver_error!(422, message: "Could not create tag because a Git pre-receive hook failed.\n\n#{e.message}")
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing, SpokesAPI::NotFound => e
      deliver_error!(422, message: "Could not verify object")
    rescue GitRPC::Failure => e
      raise unless [Rugged::OdbError, Rugged::ReferenceError].any? { |err| e.original.is_a? err }
      deliver_error!(422, message: "Could not verify object")
    end

    obj = repo.objects.read(oid, "tag")
    deliver :tag_hash, obj, repo: repo, status: 201
  end

  private

  sig { params(tagger: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def sanitize_tagger(tagger)
    time = tagger.fetch(:time)
    time = Time.iso8601(time) if time.instance_of? String

    min_time = [0, -time.utc_offset].max
    max_time = [4102444799, 4102444799 - time.utc_offset].min

    if time.to_i < min_time || time.to_i > max_time
      tagger = tagger.dup
      tagger[:time] = time.clamp(Time.at(min_time, in: time.utc_offset), Time.at(max_time, in: time.utc_offset))
    end
    tagger
  end
end
