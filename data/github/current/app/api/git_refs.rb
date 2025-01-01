# typed: true
# frozen_string_literal: true

class Api::GitRefs < Api::App
  include ReceiveSchemaWithOpenApi
  before do
    @accepted_scopes = [:repo]
  end

  # The Repository this request was made on.
  sig { returns(Repository) }
  def repo
    @repo ||= find_repo!
  end

  sig { params(name: String).returns(T.nilable(Git::Ref)) }
  def find_ref(name)
    if repo.feature_flag_enabled?(:git_refs_find_ref, default: false)
      return if name.include?("*")
      response = repo.resolve_references([name])
      ref = T.let(response.first, T.nilable([String, T.nilable(String)]))
      return if ref.nil? || ref.last.nil?
      Git::Ref.new(repo, ref.first, ref.last)
    else
      refs.find(name)
    end
  end

  sig { params(name: String, skip_preload: T::Boolean).returns(T.any(Git::Ref::Collection, T::Array[Git::Ref])) }
  def select_refs(name: "", skip_preload: false)
    ref_list = T.let([], T.any(Git::Ref::Collection, T::Array[Git::Ref]))

    if repo.feature_flag_enabled?(:git_refs_select_refs, default: false)
      unless name.include?("*")
        is_suffixed = name.end_with?("/")
        if is_suffixed
          include_prefixes = ["#{name}**/*"]
        else
          include_prefixes = ["#{name}*", "#{name}/**/*", "#{name}*/**/*"]
        end

        ref_list = begin
          SpokesAPI::Client.paged_responses do |cursor|
            repo.spokes_api.list_references(include_prefixes:, exclude_prefixes: ["refs/__gh__/**/*"], cursor:)
          end.flat_map do |response|
            response.reference_items.filter_map do |ref_item|
              Git::Ref.new(repo, ref_item.reference&.name, ref_item.object&.oid&.id) unless ref_item.object&.oid&.id.nil?
            end
          end
        rescue SpokesAPI::Error
          []
        end
      end
    else
      ref_list = if name == ""
        refs
      else
        refs.select { |ref| ref.qualified_name.match(/^#{Regexp.escape(name)}/) }
      end
    end

    if skip_preload
      return ref_list
    end
    Git::Ref::Collection.preload_target_objects(ref_list)
    ref_list.reject { |ref| ref.target.nil? }
  end

  # The refs collection used to operate on all refs in the repository.
  sig { returns(Git::Ref::Collection) }
  def refs
    repo.extended_refs
  end

  # Get the contents of a ref object
  get "/repositories/:repository_id/git/refs/*", operation_id: "git/get-all-refs" do
    control_access :get_ref,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)
    name = build_name_from_params

    set_poll_interval_header!

    if ref = refs.find(name)
      deliver :ref_hash, ref, last_modified: calc_last_modified([ref, repo])
    else
      subset = select_refs(name:)

      if subset.any?
        deliver :ref_hash, subset, last_modified: calc_last_modified([*subset, repo])
      else
        deliver_error!(404)
      end
    end
  end

  # Get the contents of a specified ref object
  get "/repositories/:repository_id/git/ref/*", operation_id: "git/get-ref" do
    control_access :get_ref,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)
    name = build_name_from_params

    set_poll_interval_header!

    ref = find_ref(name)
    record_or_404(ref)

    deliver :ref_hash, ref, last_modified: calc_last_modified_for_object(repo)
  end

  # Get the contents of any ref matching the supplied name
  get "/repositories/:repository_id/git/matching-refs/*", operation_id: "git/list-matching-refs" do
    control_access :get_ref,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)
    name = build_name_from_params

    set_poll_interval_header!

    subset = select_refs(name:)

    deliver :ref_hash, subset, last_modified: calc_last_modified_for_object(repo)
  end

  get "/repositories/:repository_id/git/refs", operation_id: :deprecated do
    @route_owner = "@github/repos"
    @documentation_url = "/rest/reference/git#get-all-references"
    control_access :list_refs,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)

    list = select_refs(skip_preload: true).to_a
    list = list.paginate(pagination)
    Git::Ref::Collection.preload_target_objects(list)

    set_poll_interval_header!
    deliver :ref_hash, list, last_modified: calc_last_modified_for_object(repo)
  end

  # Disambiguate a ref+path string into its components.
  # Used by github.dev.
  get "/repositories/:repository_id/git/extract-ref/*", operation_id: :internal do
    @route_owner = "@github/repos"
    control_access :extract_ref,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)
    combined_string = params.dig("splat", 0).to_s

    ref, path = GitHub::RefShaPathExtractor.new(repo).call(combined_string)
    deliver_error!(404, message: "No ref found") unless ref

    # API is only used as an internal API in codespaces web therefore safe to use name_with_owner here.
    response = { name_with_owner: repo.name_with_display_owner, ref: ref, path: path } # rubocop:disable GitHub/DoNotAllowNameWithOwner

    deliver_raw(response, status: 200, last_modified: repo.refset_updated_at)
  end

  # Create a new reference
  post "/repositories/:repository_id/git/refs", operation_id: "git/create-ref", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::Spokes]) do
      data = receive_with_schema("git-ref", "create-legacy")
      name = data["ref"]
      oid  = sha_param!("sha", data)

      control_access :create_ref_v2,
        repo: repo,
        before_oid: GitHub::NULL_OID,
        after_oid: oid,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_content!(repo)
      ensure_repo_writable!(repo)

      validate_ref_name name, action: "create"

      begin
        target = repo.objects.read(oid)
        reflog = request_reflog_data("git refs create api")
        ref = refs.create(name, target, current_user, reflog_data: reflog)
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:create", "valid:true"]
        deliver(:ref_hash, ref, status: 201)
      rescue Git::Ref::HookFailed => e
        deliver_error!(422, message: "Could not create ref because a Git pre-receive hook failed.\n\n#{e.message}")
      rescue GitRPC::ObjectMissing
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:create", "valid:false", "error:object_missing"]
        deliver_error!(422, message: "Object does not exist")
      rescue Git::Ref::ExistsError
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:create", "valid:false", "error:ref_exists"]
        deliver_error!(422, message: "Reference already exists")
      rescue Git::Ref::InvalidName => e
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:create", "valid:false", "error:invalid_name"]
        deliver_error!(422, message: e.message)
      rescue # rubocop:todo Lint/RescueException
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:create", "valid:false", "error:misc_error"]
        deliver_error!(422, message: "Reference update failed")
      end
    end
  end

  # Update a reference
  verbs :patch, :post, :put, "/repositories/:repository_id/git/refs/*", operation_id: "git/update-ref", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::Spokes]) do
      name = build_name_from_params

      data = receive_with_schema("git-ref", "update-legacy")
      oid  = sha_param!("sha", data)

      # We don't have safe access to the before OID
      # This will cause a larger diff to be calculated than is necessary for the workflow scope
      control_access :update_ref_v2,
        repo: repo,
        ref_name: name,
        before_oid: GitHub::NULL_OID,
        after_oid: oid,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_content!(repo)
      ensure_repo_writable!(repo)

      validate_ref_name name, action: "update"

      begin
        ref = refs.find(name)

        if ref.nil?
          GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:false", "error:not_found"]
          deliver_error!(422, message: "Reference does not exist")
        end

        target = repo.objects.read(oid)

        # special checks for branches
        if name.start_with?("refs/heads/")
          if !target.is_a?(Commit)
            GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:false", "error:not_commit"]
            deliver_error!(422, message: "Object is not a commit")
          end
        end

        # update the reference
        reflog = request_reflog_data("git refs update api")
        force = data.fetch("force") { false } # refuse force pushes by default
        ref.update(target, current_user, reflog_data: reflog, force: force)
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:true"]
        deliver :ref_hash, ref
      rescue Git::Ref::NotFastForward
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:false", "error:not_fast_forward"]
        deliver_error!(422, message: "Update is not a fast forward")
      rescue Git::Ref::HookFailed => e
        deliver_error!(422, message: "Custom Hook Failed:\n\n#{e.message}")
      rescue Git::Ref::ProtectedBranchUpdateError => e
        deliver_error!(422, message: e.result.message, documentation_url: "#{GitHub.help_url}/articles/about-protected-branches")
      rescue Git::Ref::RepositoryRuleViolationError => e
        deliver_error!(422, message: e.detailed_message)
      rescue Git::Ref::ComparisonMismatch
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:false", "error:comparison_mismatch"]
        deliver_error!(422, message: "Reference cannot be updated")
      rescue Git::Ref::UpdateFailedSensitive
        raise if repo.rpc.object_exists?(oid)

        deliver_error!(422, message: "Object does not exist")
      rescue GitRPC::ObjectMissing
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:update", "valid:false", "error:object_missing"]
        deliver_error!(422, message: "Object does not exist")
      end
    end
  end

  # Delete a reference
  delete "/repositories/:repository_id/git/refs/*", operation_id: "git/delete-ref", read_from_replicas: true do
    with_write(clusters: [ApplicationRecord::Spokes]) do
      # Introducing strict validation of the git-ref.delete
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("git-ref", "delete", skip_validation: true)

      control_access :delete_ref,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true
      ensure_repo_content!(repo)
      ensure_repo_writable!(repo)

      name = build_name_from_params
      validate_ref_name name, action: "delete"

      if ref = refs.find(name)
        if repo.feature_flag_enabled_or_raise?(:branch_deletion_protection) && ref.default_branch? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          deliver_error!(422, message: "Cannot delete the default branch")
        end

        begin
          ref.delete(current_user, reflog_data: request_reflog_data("git refs delete api"))
          GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:delete", "valid:true"]
          deliver_empty(status: 204)
        rescue Git::Ref::HookFailed => e
          deliver_error!(422, message: "Custom Hook Failed:\n\n#{e.message}")
        rescue Git::Ref::ProtectedBranchUpdateError => e
          deliver_error!(422, message: e.result.message, documentation_url: "#{GitHub.help_url}/articles/about-protected-branches")
        rescue Git::Ref::RepositoryRuleViolationError => e
          deliver_error!(422, message: e.detailed_message)
        rescue Git::Ref::ComparisonMismatch
          deliver_error!(404, message: "Reference does not exist")
        rescue GitHub::DGit::ThreepcBusyError => e
          deliver_error!(429, message: e.message)
        end
      else
        GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:delete", "valid:false", "error:not_found"]
        deliver_error!(422, message: "Reference does not exist")
      end
    end
  end

  private

  sig { returns(String) }
  def build_name_from_params
    ("refs/#{params[:splat].join("/")}").b
  end

  sig { params(ref_name: String, action: String).void }
  def validate_ref_name(ref_name, action:)
    if action == "create"
      reject_invalid_refs! ref_name, action: action
    end
    reject_internal_refs! ref_name, action: action
  end

  # On create, check that ref names satisfy some rules:
  # * Ref names must be valid git ref names
  # * Ref names must start with refs/
  # * Ref names must have three or more components (refs/tags = bad, refs/tags/ok = good)
  # action: T.any("create", "update", "delete")
  sig { params(ref_name: String, action: String).void }
  def reject_invalid_refs!(ref_name, action:)
    case
    when !Rugged::Reference.valid_name?(ref_name)
      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:invalid_name"]
      deliver_error! 422, message: "#{ref_name} is not a valid ref name."
    when ref_name !~ %r{\Arefs/}
      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:not_under_refs"]
      deliver_error! 422, message: "Reference name must start with 'refs/'."
    when ref_name !~ %r{\Arefs/[^/]+/[^/]}
      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:fewer_than_three_components"]
      deliver_error! 422, message: "Reference name must contain at least three slash-separated components."
    end
  end

  MERGE_QUEUE_REF_REGEX = %r{\A#{MergeQueue::READ_ONLY_REF_PREFIX.delete_suffix('/')}(/|\z)}

  # On any write, check that the ref name is not supposed to be read-only.
  # * refs/pull/* relate to pull requests.
  # * refs/__gh__/* are used for various other internal bits.
  # * refs/gh/queue/* are used for merge queue references.
  # action: T.any("create", "update", "delete")
  sig { params(ref_name: String, action: String).void }
  def reject_internal_refs!(ref_name, action:)
    case ref_name
    when %r{\Arefs/pull(/|\z)}
      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:refs_pull"]
      deliver_error! 422, message: "refs/pull/* is read-only."
    when MERGE_QUEUE_REF_REGEX
      return unless repo.merge_queue_enabled?

      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:refs_merge_queue"]
      deliver_error! 422, message: "#{MergeQueue::READ_ONLY_REF_PREFIX}* is read-only."
    when %r{\Arefs/__gh__(/|\z)}
      GitHub.dogstats.increment "git_ref", tags: ["via:api", "action:#{action}", "valid:false", "error:refs_gh"]
      deliver_error! 422, message: "refs/__gh__/* is reserved for internal use."
    end
  end

  sig { returns(ActiveSupport::Duration) }
  def poll_interval
    5.minutes
  end
end
