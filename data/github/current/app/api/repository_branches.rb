# typed: true
# frozen_string_literal: true

class Api::RepositoryBranches < Api::App
  include ReceiveSchemaWithOpenApi

  map_to_service :repos, only: [ # rubocop:todo GitHub/MapToService
    "GET /repositories/:repository_id/branches",
    "GET /repositories/:repository_id/branches/*",
    "POST /repositories/:repository_id/branches/*/rename",
    "POST /repositories/:repository_id/branches/*/merge-upstream",
    "POST /repositories/:repository_id/merges"
  ]

  map_to_service :branch_protection_rule, only: [ # rubocop:todo GitHub/MapToService
    "GET /repositories/:repository_id/branches/*/protection",
    "PUT /repositories/:repository_id/branches/*/protection",
    "DELETE /repositories/:repository_id/branches/*/protection",
    "GET /repositories/:repository_id/branches/*/push_control",
    "GET /repositories/:repository_id/branches/*/protection/required_status_checks",
    "PATCH /repositories/:repository_id/branches/*/protection/required_status_checks",
    "DELETE /repositories/:repository_id/branches/*/protection/required_status_checks",
    "GET /repositories/:repository_id/branches/*/protection/required_status_checks/contexts",
    "PUT /repositories/:repository_id/branches/*/protection/required_status_checks/contexts",
    "POST /repositories/:repository_id/branches/*/protection/required_status_checks/contexts",
    "DELETE /repositories/:repository_id/branches/*/protection/required_status_checks/contexts",
    "GET /repositories/:repository_id/branches/*/protection/restrictions",
    "DELETE /repositories/:repository_id/branches/*/protection/restrictions",
    "GET /repositories/:repository_id/branches/*/protection/restrictions/users",
    "PUT /repositories/:repository_id/branches/*/protection/restrictions/users",
    "POST /repositories/:repository_id/branches/*/protection/restrictions/users",
    "DELETE /repositories/:repository_id/branches/*/protection/restrictions/users",
    "GET /repositories/:repository_id/branches/*/protection/restrictions/teams",
    "PUT /repositories/:repository_id/branches/*/protection/restrictions/teams",
    "POST /repositories/:repository_id/branches/*/protection/restrictions/teams",
    "DELETE /repositories/:repository_id/branches/*/protection/restrictions/teams",
    "GET /repositories/:repository_id/branches/*/protection/restrictions/apps",
    "PUT /repositories/:repository_id/branches/*/protection/restrictions/apps",
    "POST /repositories/:repository_id/branches/*/protection/restrictions/apps",
    "DELETE /repositories/:repository_id/branches/*/protection/restrictions/apps",
    "GET /repositories/:repository_id/branches/*/protection/required_pull_request_reviews",
    "PATCH /repositories/:repository_id/branches/*/protection/required_pull_request_reviews",
    "DELETE /repositories/:repository_id/branches/*/protection/required_pull_request_reviews",
    "GET /repositories/:repository_id/branches/*/protection/required_signatures",
    "POST /repositories/:repository_id/branches/*/protection/required_signatures",
    "DELETE /repositories/:repository_id/branches/*/protection/required_signatures",
    "GET /repositories/:repository_id/branches/*/protection/enforce_admins",
    "POST /repositories/:repository_id/branches/*/protection/enforce_admins",
    "DELETE /repositories/:repository_id/branches/*/protection/enforce_admins"
  ]

  # list branches for a repository
  get "/repositories/:repository_id/branches", operation_id: "repos/list-branches" do
    control_access :list_branches,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    branches = repo.heads.to_a

    protection_status = parse_bool(params[:protected])

    unless protection_status.nil?
      if GitHub.flipper[:use_branch_evaluator_for_branches_api].enabled?(repo)
        GitHub::PrefillAssociations.prefill_batch_method(branches, :policy_evaluator)
        protected_branches = branches.filter { |branch| branch.protected? }

        if protection_status == true
          branches = protected_branches
        elsif protection_status == false
          branches = branches - protected_branches
        end
      else
        # get the branch names from the ref objects
        branch_names = branches.map(&:name)
        # Find the branches that have branch protections and rules
        protected_branch_names = ProtectedBranch.for_repository_with_branch_names(repo, branch_names).select { |_, value| value }.keys
        ruleset_branch_names = repo.protected_by_rulesets(branch_names)
        branch_names = protected_branch_names | ruleset_branch_names
        # go back and select the full ref objects
        if protection_status == true
          branches = branches.select { |branch| branch_names.include?(branch.name) }
        elsif protection_status == false
          branches = branches.reject { |branch| branch_names.include?(branch.name) }
        end
      end
    end

    branches = branches.paginate(pagination)

    # This prefill is a temporary fix for the performance issues caused by `short_branch_with_protection_hash`
    # The "pushability" and "protection" API responses do not currently consider Ruleset rules (via policy_evaluator)
    # and therefore reload the BranchProtection objects for each branch.
    # TODO: Use `policy_evaluator` for these responses
    GitHub::PrefillAssociations.prefill_batch_method(branches, :protected_branch)
    GitHub::PrefillAssociations.prefill_batch_method(branches, :policy_evaluator)

    can_read_branch_protections = if repo.plan_supports?(:protected_branches)
      access_allowed?(:read_branch_protection, {
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
      })
    else
      false
    end

    if can_read_branch_protections
      deliver :short_branch_with_protection_hash, branches
    else
      deliver :short_branch_hash, branches
    end
  end

  # merge one branch into another
  post "/repositories/:repository_id/merges", operation_id: "repos/merge" do
    repo = find_repo!
    control_access :merge_branch,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_writable!(repo)

    data = receive_with_schema("merge", "create-legacy")

    base, head, message = data.values_at("base", "head", "commit_message")

    base_ref = repo.heads.find(base)

    deliver_error!(404,
      message: "Base does not exist",
      documentation_url: @documentation_url) unless base_ref

    head_sha = repo.ref_to_sha(head)
    deliver_error!(404,
      message: "Head does not exist",
      documentation_url: @documentation_url) unless head_sha.present?

    begin
      control_access :update_ref_v2,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        repo: repo,
        user: current_user,
        before_oid: base_ref.sha,
        after_oid: head_sha
    rescue GitRPC::ObjectMissing
      deliver_error!(404,
        message: "Head does not exist",
        documentation_url: @documentation_url)
    end

    begin
      merge_commit, error, error_message = base_ref.merge(current_user, head, {
        commit_message: message,
        reflog_data: request_reflog_data("branch merge api"),
      })

      if merge_commit
        emit_telemetry_when_invalid_signature(merge_commit, repo)
        deliver(:git_commit_hash, merge_commit, status: 201)
      else
        case error
        when :no_such_head
          deliver_error!(404,
            message: "Head does not exist",
            documentation_url: @documentation_url)
        when :already_merged
          deliver_empty(status: 204)
        when :merge_conflict, :protected_branch_update_error, :repository_rule_violation, :workflow_policy_update_error
          deliver_error(409,
            message: error_message,
            documentation_url: @documentation_url)
        else
          deliver_error(500,
            message: "There was a problem performing the merge",
            documentation_url: @documentation_url)
        end
      end
    rescue Git::Ref::HookFailed => e
      deliver_error 422,
      message: "Could not merge because a Git pre-receive hook failed.\n\n#{e.message}",
      documentation_url: @documentation_url
    end
  end

  # Emit telemetry in case we just signed the commit with our GitHub signing key and the signature is invalid
  def emit_telemetry_when_invalid_signature(merge_commit, repo)
    return if GitHub.enterprise?
    return if merge_commit.verified_signature? == true

    GitHub.dogstats.increment("gpg.merge_api_signature_invalid")

    begin
      GitHub.logger.info("GPG merge API signature invalid", {
        "gh.commit.oid" => merge_commit.oid,
        "gh.repo.id" => repo.id,
        "gh.repo.name_with_owner" => repo.name_with_owner_for_api,
        "gh.commit.key_id" => merge_commit.signature_issuer_key_id_hex || merge_commit.ssh_key_fingerprint_hex,

        # The props below are used in `def verification_hash` and already returned from the API
        # So we assume it shouldn't add additional queries and performance drawback here
        "gh.verification.verified_signature" => merge_commit.verified_signature?,
        "gh.verification.signature_verification_reason" => merge_commit.signature_verification_reason,
        "gh.verification.signature" => merge_commit.signature,
        "gh.verification.signing_payload" => merge_commit.signing_payload,
      })
    # Rescue in case some property above is not present on the commit object, because who knows
    rescue NoMethodError => e
      GitHub.dogstats.increment("gpg.merge_api_signature_invalid.no_method_error")
      Failbot.report e
    end
  end

  post "/repositories/:repository_id/merge-upstream", operation_id: "repos/merge-upstream" do
    repo = find_repo!

    if @operation.nil?
      raise "@operation needs to be set for OpenAPI request validation. Make sure you are using :operation_id when defining your endpoint."
    end
    request.body.rewind
    data = receive(nil, required: true)
    result = validate_with_openapi(
      data: data,
      operation: @operation,
      request: request
    )
    if !result.valid?
      control_access :merge_upstream,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      error_messages = result.errors.map(&:public_error).join("\n")
      deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
    end

    branch = data.fetch("branch")

    ref = repo.heads.find(branch)
    ensure_branch_exists!(ref)

    control_access :merge_upstream,
      resource: repo,
      ref: ref,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error_if_archived!(repo)
    ensure_repo_writable!(repo)

    begin
      success_details = ref.fetch_and_merge(actor: current_user)
      deliver(:merged_upstream,
        {
          message: success_details[:message],
          merge_type: success_details[:merge_type],
          base_branch: success_details[:base_branch]
        }
      )
    rescue Git::Ref::RejectedError
      deliver_error! 422
    rescue Git::Ref::MergeConflictError
      deliver_error!(409, message: "There are merge conflicts")
    rescue Git::Ref::FetchAndMergeFailure => e
      deliver_error!(422, message: e.ui_message)
    end
  end

  # Get protection status
  get "/repositories/:repository_id/branches/*/protection", operation_id: "repos/get-branch-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)

    deliver(:protected_branch_hash, ref)
  end

  def extract_required_pull_request_reviews(data)
    return if data["required_pull_request_reviews"].nil?

    object = data["required_pull_request_reviews"]

    keys = %w[
      dismissal_restrictions
      dismiss_stale_reviews
      require_code_owner_reviews
      required_approving_review_count
      require_last_push_approval
    ]

    object.slice(*keys).symbolize_keys!
  end

  def extract_restrictions(data)
    return if data.nil?

    {
      users: data["users"],
      teams: data["teams"],
      integrations: data["apps"],
    }
  end

  # Enable branch protection
  put "/repositories/:repository_id/branches/*/protection", operation_id: "repos/update-branch-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)

    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists!(ref)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "enable-legacy")

    result = BranchProtector.new(repository: repo, actor: current_user, ref_name: ref.name, data: data, include_required_signatures: true, entry_point: :rest_api_repository_protected_branch_enable).protect_branch

    if result.success?
      ref.protected_branch = result.protected_branch
      deliver(:protected_branch_hash, ref)
    else
      deliver_error 422, errors: result.errors
    end
  end

  # Disable branch protection
  delete "/repositories/:repository_id/branches/*/protection", operation_id: "repos/delete-branch-protection" do
    # Introducing strict validation of the protected-branch.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "delete", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    ref.protected_branch.destroy_with_args(entry_point: :rest_api_branch_protection_delete) if ref.protected_by_exact_rule?

    deliver_empty(status: 204)
  end

  # Can the current user push to a branch?
  get "/repositories/:repository_id/branches/*/push_control", operation_id: :unreleased do
    @route_owner = "@github/repos"

    repo = find_repo!

    control_access :list_branches,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/push_control")
    ref ||= Git::Ref.new(repo, params[:splat].first, nil, "refs/heads/")

    deliver :branch_pushability_hash, ref
  end

  # Get required status check settings
  get "/repositories/:repository_id/branches/*/protection/required_status_checks", operation_id: "repos/get-status-checks-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)

    deliver(:protected_branch_required_status_checks_hash, ref)
  end

  # Update required status check settings
  patch "/repositories/:repository_id/branches/*/protection/required_status_checks", operation_id: "repos/update-status-check-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "update-required-status-checks-legacy")

    begin
      with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_status_check_update) do |protected_branch|
        required_status_checks = BranchProtector.extract_required_status_checks(repo, data) || {}
        protected_branch.update_required_status_checks(**required_status_checks)
        protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_required_status_check_update)
      end

      deliver(:protected_branch_required_status_checks_hash, ref)
    rescue BranchProtector::DuplicatedContextError => e
      deliver_error! 422, message: e.message
    end
  end

  # Disable required status checks
  delete "/repositories/:repository_id/branches/*/protection/required_status_checks", operation_id: "repos/remove-status-check-protection" do
    # Introducing strict validation of the protected-branch.remove-required-status-checks
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "remove-required-status-checks", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_status_check_disable) do |protected_branch|
      protected_branch.clear_required_status_checks
      protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_required_status_check_disable)
    end

    deliver_empty(status: 204)
  end

  # Get required status check contexts
  get "/repositories/:repository_id/branches/*/protection/required_status_checks/contexts", operation_id: "repos/get-all-status-check-contexts" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks/contexts")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)

    deliver(:raw, ref.protected_branch.required_status_checks.map(&:context))
  end

  # Replace required status check contexts
  put "/repositories/:repository_id/branches/*/protection/required_status_checks/contexts", operation_id: "repos/set-status-check-contexts" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks/contexts")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["contexts"] : data

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_status_check_context_replace) do |protected_branch|
        protected_branch.replace_status_contexts(data)
        protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_required_status_check_context_replace)
      end

      deliver(:raw, protected_branch.required_status_checks.map(&:context))
    rescue ActiveRecord::RecordInvalid => e
      deliver_error 422, errors: e.record.errors
    end
  end

  # Add required status check contexts
  post "/repositories/:repository_id/branches/*/protection/required_status_checks/contexts", operation_id: "repos/add-status-check-contexts" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks/contexts")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["contexts"] : data

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_status_check_context_add) do |protected_branch|
        protected_branch.create_required_status_checks(data)
        protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_required_status_check_context_add)
      end

      deliver(:raw, protected_branch.required_status_checks.map(&:context))
    rescue ActiveRecord::RecordInvalid => e
      deliver_error 422, errors: e.record.errors
    end
  end

  # Delete required status check contexts
  delete "/repositories/:repository_id/branches/*/protection/required_status_checks/contexts", operation_id: "repos/remove-status-check-contexts" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_status_checks/contexts")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_required_status_checks_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["contexts"] : data

    protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_status_check_context_delete) do |protected_branch|
      protected_branch.destroy_required_status_checks(data)
      protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_required_status_check_context_delete)
    end

    deliver(:raw, protected_branch.required_status_checks.map(&:context))
  end

  # Get push restrictions settings
  get "/repositories/:repository_id/branches/*/protection/restrictions", operation_id: "repos/get-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)

    deliver(:protected_branch_restrictions_hash, ref)
  end

  # Disable push restrictions
  delete "/repositories/:repository_id/branches/*/protection/restrictions", operation_id: "repos/delete-access-restrictions" do
    # Introducing strict validation of the protected-branch.remove-restrictions
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "remove-restrictions", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_disable) do |protected_branch|
      protected_branch.clear_restrictions
      protected_branch.save_with_args!(entry_point: :rest_api_repository_protected_branch_push_restriction_disable)
    end

    deliver_empty(status: 204)
  end

  # Get list of users restricted to pushing
  get "/repositories/:repository_id/branches/*/protection/restrictions/users", operation_id: "repos/get-users-with-access-to-protected-branch" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/users")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)

    deliver(:simple_user_hash, ref.protected_branch.authorized_users)
  end

  # Replace list of users restricted to pushing
  put "/repositories/:repository_id/branches/*/protection/restrictions/users", operation_id: "repos/set-user-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/users")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "replace-user-restrictions-legacy")

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_update) do |protected_branch|
        protected_branch.update_restrictions(users: data, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_update)
      end

      deliver(:simple_user_hash, protected_branch.authorized_users)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Add list of users restricted to pushing
  post "/repositories/:repository_id/branches/*/protection/restrictions/users", operation_id: "repos/add-user-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/users")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "add-user-restrictions-legacy")

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_add) do |protected_branch|
        protected_branch.add_users_to_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_add)
      end

      deliver(:simple_user_hash, protected_branch.authorized_users)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Remove list of users restricted to pushing
  delete "/repositories/:repository_id/branches/*/protection/restrictions/users", operation_id: "repos/remove-user-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/users")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "remove-user-restrictions-legacy")

    protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_delete) do |protected_branch|
      protected_branch.remove_users_from_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_user_list_delete)
    end

    deliver(:simple_user_hash, protected_branch.authorized_users)
  end

  # Get list of teams restricted to pushing
  get "/repositories/:repository_id/branches/*/protection/restrictions/teams", operation_id: "repos/get-teams-with-access-to-protected-branch" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/teams")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)

    deliver(:team_hash, ref.protected_branch.authorized_teams_with_preloaded_org)
  end

  # Replace list of teams restricted to pushing
  put "/repositories/:repository_id/branches/*/protection/restrictions/teams", operation_id: "repos/set-team-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/teams")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["teams"] : data

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_update) do |protected_branch|
        protected_branch.update_restrictions(teams: data, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_update)
      end

      deliver(:team_hash, protected_branch.authorized_teams_with_preloaded_org)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Add list of teams restricted to pushing
  post "/repositories/:repository_id/branches/*/protection/restrictions/teams", operation_id: "repos/add-team-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/teams")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["teams"] : data

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_add) do |protected_branch|
        protected_branch.add_teams_to_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_add)
      end

      deliver(:team_hash, protected_branch.authorized_teams_with_preloaded_org)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Remove list of teams restricted to pushing
  delete "/repositories/:repository_id/branches/*/protection/restrictions/teams", operation_id: "repos/remove-team-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/teams")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_openapi
    data = data.is_a?(Hash) ? data["teams"] : data

    protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_delete) do |protected_branch|
      protected_branch.remove_teams_from_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_team_list_delete)
    end

    deliver(:team_hash, protected_branch.authorized_teams_with_preloaded_org)
  end

  # Get list of apps restricted to pushing
  get "/repositories/:repository_id/branches/*/protection/restrictions/apps", operation_id: "repos/get-apps-with-access-to-protected-branch" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/apps")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)

    integrations = ref.protected_branch.authorized_integrations.includes([:owner, :bot, :latest_version])

    deliver(:integration_hash, integrations)
  end

  # Replace list of apps restricted to pushing
  put "/repositories/:repository_id/branches/*/protection/restrictions/apps", operation_id: "repos/set-app-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/apps")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "replace-app-restrictions-legacy")

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_update) do |protected_branch|
        protected_branch.update_restrictions(integrations: data, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_update)
      end

      integrations = protected_branch.authorized_integrations.includes([:owner, :bot, :latest_version])

      deliver(:integration_hash, integrations)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Add list of apps restricted to pushing
  post "/repositories/:repository_id/branches/*/protection/restrictions/apps", operation_id: "repos/add-app-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/apps")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "add-app-restrictions-legacy")

    begin
      protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_add) do |protected_branch|
        protected_branch.add_integrations_to_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_add)
      end

      integrations = protected_branch.authorized_integrations.includes([:owner, :bot, :latest_version])

      deliver(:integration_hash, integrations)
    rescue ProtectedBranch::TooManyPermittedActors => err
      deliver_error 422, errors: [err.message]
    end
  end

  # Remove list of apps restricted to pushing
  delete "/repositories/:repository_id/branches/*/protection/restrictions/apps", operation_id: "repos/remove-app-access-restrictions" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/restrictions/apps")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_push_restrictions_enabled!(ref.protected_branch)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "remove-app-restrictions-legacy")

    protected_branch = with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_delete) do |protected_branch|
      protected_branch.remove_integrations_from_restrictions(data, entry_point: :rest_api_repository_protected_branch_push_restriction_app_list_delete)
    end

    integrations = protected_branch.authorized_integrations.includes([:owner, :bot, :latest_version])

    deliver(:integration_hash, integrations)
  end

  # Get pull request review enforcement settings
  get "/repositories/:repository_id/branches/*/protection/required_pull_request_reviews", operation_id: "repos/get-pull-request-review-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_pull_request_reviews")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)

    deliver(:protected_branch_pull_request_reviews_hash, ref)
  end

  # Update pull request review enforcement settings
  patch "/repositories/:repository_id/branches/*/protection/required_pull_request_reviews", operation_id: "repos/update-pull-request-review-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_pull_request_reviews")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    data = receive_with_schema("protected-branch", "update-pull-request-review-enforcement-legacy")

    deliver_error!(422, message: "Dismissal restrictions are supported only for repositories owned by an organization.") if data["dismissal_restrictions"] && !repo.in_organization?

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_pull_request_review_enforcement_update) do |protected_branch|
      protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: data["dismiss_stale_reviews"],
        require_code_owner_reviews: data["require_code_owner_reviews"],
        required_approving_review_count: data["required_approving_review_count"],
        dismissal_restrictions: data["dismissal_restrictions"],
        bypass_pull_request_allowances: data["bypass_pull_request_allowances"],
        require_last_push_approval: data["require_last_push_approval"]
      )

      unless protected_branch.save_with_args(entry_point: :rest_api_repository_protected_branch_pull_request_review_enforcement_update)
        deliver_error! 422, errors: protected_branch.errors
      end
    end

    deliver(:protected_branch_pull_request_reviews_hash, ref)
  end

  # Remove pull request review enforcement settings
  delete "/repositories/:repository_id/branches/*/protection/required_pull_request_reviews", operation_id: "repos/delete-pull-request-review-protection" do
    # Introducing strict validation of the protected-branch.remove-pr-review-enforcement
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "remove-pr-review-enforcement", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_pull_request_reviews")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_pull_request_review_enforcement_delete) do |protected_branch|
      protected_branch.clear_required_pull_request_reviews
      protected_branch.save_with_args(entry_point: :rest_api_repository_protected_branch_pull_request_review_enforcement_delete)
    end

    deliver_empty(status: 204)
  end

  # Get required signatures setting
  get "/repositories/:repository_id/branches/*/protection/required_signatures", operation_id: "repos/get-commit-signature-protection" do

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_signatures")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)

    deliver(:protected_branch_required_signatures_hash, ref)
  end

  # Enable required signatures setting
  post "/repositories/:repository_id/branches/*/protection/required_signatures", operation_id: "repos/create-commit-signature-protection" do

    receive_with_schema("protected-branch", "enable-required-signatures")

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_signatures")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_signatures_enable) do |protected_branch|
      protected_branch.enable_required_signatures

      unless protected_branch.save_with_args(entry_point: :rest_api_repository_protected_branch_required_signatures_enable)
        deliver_error! 422, errors: protected_branch.errors
      end
    end

    deliver(:protected_branch_required_signatures_hash, ref)
  end

  # Disable required signatures setting
  delete "/repositories/:repository_id/branches/*/protection/required_signatures", operation_id: "repos/delete-commit-signature-protection" do

    # Introducing strict validation of the protected-branch.remove-required-signatures
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "remove-required-signatures", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/required_signatures")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_required_signatures_disable) do |protected_branch|
      protected_branch.clear_required_signatures

      unless protected_branch.save_with_args(entry_point: :rest_api_repository_protected_branch_required_signatures_disable)
        deliver_error! 422, errors: protected_branch.errors
      end
    end

    deliver_empty(status: 204)
  end

  # Get admin enforcement settings
  get "/repositories/:repository_id/branches/*/protection/enforce_admins", operation_id: "repos/get-admin-branch-protection" do
    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/enforce_admins")

    control_access :read_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_branch_exists_and_is_protected!(ref)

    deliver(:protected_branch_admin_enforced_hash, ref)
  end

  # Update admin enforcement settings
  post "/repositories/:repository_id/branches/*/protection/enforce_admins", operation_id: "repos/set-admin-branch-protection" do
    receive_with_schema("protected-branch", "enable-admin-enforcement")

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/enforce_admins")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_admin_enforcement_update) do |protected_branch|
      unless protected_branch.update(admin_enforced: true)
        deliver_error! 422, errors: protected_branch.errors
      end
    end

    deliver(:protected_branch_admin_enforced_hash, ref)
  end

  # Remove admin enforcement settings
  delete "/repositories/:repository_id/branches/*/protection/enforce_admins", operation_id: "repos/delete-admin-branch-protection" do
    # Introducing strict validation of the protected-branch.remove-admin-enforcement
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("protected-branch", "remove-admin-enforcement", skip_validation: true)

    repo = find_repo!
    ensure_plan_supports_protected_branches!(repo) unless repo.feature_enabled?(:bp_check_access_before_plan)

    ref = repo.heads.find(params[:splat].first)
    pass if ref.nil? && ref_with_suffix_exists?(repo, suffix: "/protection/enforce_admins")

    control_access :update_branch_protection,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_plan_supports_protected_branches!(repo) if repo.feature_enabled?(:bp_check_access_before_plan)
    ensure_user_can_update_branch_protection!(repo, current_user)
    ensure_branch_exists_and_is_protected!(ref)
    ensure_repo_writable!(repo)

    with_protected_branch_for_modification(ref, entry_point: :rest_api_repository_protected_branch_admin_enforcement_delete) do |protected_branch|
      unless protected_branch.update(admin_enforced: false)
        deliver_error! 422, errors: protected_branch.errors
      end
    end

    deliver_empty(status: 204)
  end

  # get a single branch and the commit it points to
  # uses splat route to accommodate branches with slashes
  get "/repositories/:repository_id/branches/*", operation_id: "repos/get-branch" do
    control_access :list_branches,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref = repo.heads.find(params[:splat].first)

    if ref && ref.exist?
      deliver(:branch_with_protection_hash, ref)
    else
      result = RepositoryBranchRename::Detector.call(repository: repo, full_path: params[:splat].first, all_possible_names: false)
      if result.includes_renamed_branch?
        deliver_redirect!(api_url("/repos/#{repo.name_with_display_owner}/branches/#{result.redirect_branch}"), status: 301)
      else
        deliver_error(404,
          message: "Branch not found",
          documentation_url: @documentation_url)
      end
    end
  end

  post "/repositories/:repository_id/branches/*/rename", operation_id: "repos/rename-branch" do
    repo = find_repo!
    ensure_repo_writable!(repo)

    ref = repo.heads.find(params[:splat].first)
    ensure_branch_exists!(ref)

    authz_msg = if !access_allowed?(:get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true)
      nil # Don't set forbidden message. Will fall back to 404.
    elsif ref.default_branch?
      "Must have admin access to rename the default branch."
    elsif ref.protected_by_org_ruleset?
      "Must have organization admin access to rename branches protected by organization rulesets."
    elsif ref.protected?
      "Must have admin access to rename protected branches."
    else
      "Must have push access to rename git branch."
    end
    set_forbidden_message(authz_msg) if authz_msg

    control_access :rename_branch,
      resource: repo,
      ref: ref,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    new_name = receive_with_schema("branch", "rename")["new_name"]
    renamer = RepositoryBranchRenamer.for_starting_rename_process(repository: repo, branch_name: ref.name)

    if renamer.start_rename(new_name, actor: current_user, entry_point: :rest_api_repository_branch_rename)
      renamed_ref = repo.heads.find(renamer.new_name) # Use scrubbed new name
      deliver(:branch_with_protection_hash, renamed_ref, status: 201)
    else
      if renamer.rename&.started? && !renamer.rename&.new_record?
        GitHub.logger.info("Fixed Rename stuck in starting state", {
          "code.namespace": self.class.name,
          "code.function": "repos/rename-branch",
          "gh.repo.id": repo.id,
          "gh.branch_protection_rule.repository_branch_renamer.id": renamer.rename&.id,
          "gh.branch_protection_rule.repository_branch_renamer.human_error": renamer.human_error
        })
        renamer.rename&.errored!
      end
      deliver_error! 422, errors: [renamer.human_error]
    end
  end

  private

  def ref_with_suffix_exists?(repo, suffix:)
    repo.heads.find("#{params[:splat].first}#{suffix}")
  end

  # Execute the given block with a ProtectedBranch instance that is
  # suitable for modification.
  #
  # This method is supposed to help bridging compatibility between
  # "legacy" branch protections and "new-style" branch protection rules.
  #
  # When given a `Ref` for a branch for which to update protection settings,
  # this method checks whether protection is currently provided by a
  # wildcard rule or a branch-specific rule. For wildcard rules, the rule will
  # be copied to a branch-specific rule with all associated settings
  # in place, and all further protection setting modifications will be
  # performed on this newly created rule. For exact rules, the existing
  # rule will be modified directly.
  #
  # This ensures that all modifications made via the branch protections API are
  # always scoped to just a single branch, and that even partial modifications
  # end up with the same protection settings.
  #
  # ref - a `Ref` for the branch for which the protection should be changed.
  # entry_point - Symbol, the unique identifier passed to the Permissions
  #               service for instrumentation purposes.
  #
  # Returns the modified ProtectedBranch.
  def with_protected_branch_for_modification(ref, entry_point:)
    raise ArgumentError.new("The ref must have a protected branch") unless ref.protected?

    ProtectedBranch.transaction do
      Ability.transaction do
        protected_branch = if ref.protected_by_exact_rule?
          ref.protected_branch
        else
          ref.protected_branch = ref.protected_branch.deep_copy_as!(name: ref.name, creator: current_user, entry_point: entry_point)
        end

        yield protected_branch

        protected_branch
      end
    end
  end

  def ensure_branch_exists!(ref)
    if ref.nil? || !ref.exists?
      deliver_error!(404, message: "Branch not found")
    end
  end

  def ensure_branch_exists_and_is_protected!(ref)
    ensure_branch_exists!(ref)

    if ref.protected_branch.nil?
      deliver_error!(404, message: "Branch not protected")
    end
  end

  def ensure_required_status_checks_enabled!(protected_branch)
    unless protected_branch.required_status_checks_enabled?
      deliver_error! 404, message: "Required status checks not enabled"
    end
  end

  def ensure_push_restrictions_enabled!(protected_branch)
    unless protected_branch.has_authorized_actors?
      deliver_error! 404, message: "Push restrictions not enabled"
    end
  end

  def ensure_plan_supports_protected_branches!(repo)
    unless repo.plan_supports?(:protected_branches)
      deliver_error!(403, message: "Upgrade to GitHub Pro or make this repository public to enable this feature.")
    end

    if BranchProtectionsConfig.new(repo).branch_protection_disabled?
      deliver_error!(404, message: "Branch protection has been disabled on this repository.")
    end
  end

  def ensure_user_can_update_branch_protection!(repo, user)
    unless repo.can_update_protected_branches?(user)
      deliver_error!(403, message: "Protected branch updating is disabled on this repository.")
    end
  end

  def ensure_required_pull_request_reviews_enabled!(protected_branch)
    unless protected_branch.pull_request_reviews_enabled?
      deliver_error! 404, message: "Pull request review enforcement not enabled"
    end
  end
end
