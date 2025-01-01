# typed: true
# frozen_string_literal: true

class Api::Codespaces::Public < Api::Codespaces
  include Api::App::ContentHelpers
  include Api::Codespaces::Helpers::LifecycleHelpers

  before do
    @accepted_scopes = [:codespace]
  end

  # Allows us to use the `method:` condition in the filters below
  set(:method) do |method|
    method = method.to_s.upcase
    condition { T.unsafe(self).request.request_method == method }
  end

  CREATE_PATHS = ["/user/codespaces", "/repositories/:repository_id/codespaces", "/repositories/:repository_id/pulls/:pull_number/codespaces"]
  CREATE_PATHS.each do |path|
    before path, method: :post do
      @codespace_async_operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace)
      request.env["codespaces.async_operation_created"] = true
    end

    after path, method: :post do
      T.unsafe(self).ensure_async_operation_behavior(:create_codespace)
    end
  end

  after "/user/codespaces/:codespace_name/start", method: :post do
    T.unsafe(self).ensure_async_operation_behavior(:start_codespace)
  end

  ORG_CODESPACES_NOT_SUPPORTED_MESSAGE = "This organization does not support Codespaces"
  MUST_SUPPLY_REPO_ID_MESSAGE = "Must supply 'repository_id'"
  AT_CODESPACE_LIMIT_MESSAGE = "You have reached the codespace limit. Please delete an existing codespace before creating a new one."
  NO_MACHINE_TYPES_MESSAGE = "There are currently no machine types available for which you have access. Please check the repository's devcontainer configuration or contact support."
  USER_NOT_AUTHORIZED_FOR_RAW_ENVIRONMENT_MESSAGE = "User is not authorized to use environment options"
  CODESPACE_ALREADY_RUNNING = "The codespace is already running"
  INVALID_REF = "The 'ref' provided was invalid. Please specify a valid branch name or commit SHA"
  EXPORT_ALREADY_UNDERWAY_MESSAGE = "An export of that codespace is already in progress."
  CODESPACE_MUST_BE_PROVISIONED_MESSAGE = "Codespace must be provisioned"
  CODESPACE_CANNOT_BE_CREATED_MESSAGE = "You cannot create codespaces from this repository."
  CODESPACE_STILL_PROVISIONING_MESSAGE = "This codespace is still being provisioned, please try again in a few seconds."
  EMU_NOT_BILLABLE_FOR_CODESPACES_MESSAGE = "Enterprise-managed users can only use codespaces where usage is paid for by an organization in their enterprise."
  IP_ALLOWLISTS_NOT_SUPPORTED_MESSAGE = "Your organization or enterprise enforces IP allow lists which are unsupported by Codespaces at this time."
  CANT_PUSH_OR_FORK_MESSAGE = "You do not have access to push to this repository and its owner has disabled forking."
  CODESPACE_NOT_SUSPENDABLE_MESSAGE = "The codespace is not in a stoppable state, please try again or delete the codespace."
  AUTO_PUSH_NOT_SUPPORTED_FOR_PUBLIC_REPOS_MESSAGE = "You cannot enable auto push for public repositories"
  AUTO_PUSH_NOT_SUPPORTED_FOR_UNPUSHABLE_REPOS_MESSAGE = "You cannot enable auto push for repositories you cannot push to"

  # List codespaces
  get "/user/codespaces", operation_id: "codespaces/list-for-authenticated-user" do
    with_aggressive_client_timeouts do
      control_access :list_codespaces_public,
        resource: current_user,
        challenge: true,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless ::GitHub.codespaces_enabled?

      repository_id = params[:repository_id]
      if current_user.using_auth_via_integration?
        installation = current_user.oauth_access.installation
        if installation.is_a?(SiteScopedIntegrationInstallation)
          # SiteScopedIntegrationInstallation means that this is a token from the global Codespaces app from inside a codespace
          # We want to filter the codespaces to only those from the same repository
          if codespace = Codespace.find_by(id: installation.codespace_ids.first)
            set_exception_context(codespace)
            repository_id = codespace.repository_id
          else
            # A bit of defensive coding in case a codespace can have an active token used for auth but also be deleted. In that case
            # we wouldn't be able to determine which repository to scope things to so to be safe in this edge case we just bail.
            deliver_error! 404
          end
        end
      end

      codespaces, unauthorized_org_ids = find_codespaces(owner: current_user, repository_id: repository_id, filtering_resource: "codespaces")

      set_sso_partial_results_header(unauthorized_org_ids) if unauthorized_org_ids.length > 0
      # Preload associations to avoid N+1 queries...
      Codespace.prefill_associations_for_dashboard(codespaces)
      codespaces = paginate_rel(codespaces)

      data = { codespaces: codespaces, total_count: codespaces.total_entries }

      wants_internal_data = params[:internal]

      if wants_internal_data
        data[:feature_flags] = Codespaces::Vscs.feature_flags(current_user).merge(Codespaces::Jetbrains.feature_flags(current_user))
      end

      deliver :public_codespaces_hash, data, private: GitHub.flipper[:codespaces_developer].enabled?(current_user)
    end
  end

  # Get a specific codespace by name
  get "/user/codespaces/:codespace_name", operation_id: "codespaces/get-for-authenticated-user" do
    with_aggressive_client_timeouts do
      deliver_error! 404 unless GitHub.codespaces_enabled?
      # This needs to be marked as a legacy endpoint until we're able to confirm old versions of the vscode extension don't rely on being able to access codespaces from different repositories
      codespace = find_codespace!(
        owner: current_user,
        name: params[:codespace_name],
        legacy_endpoint: true,
        include_copilot_workspace: !!current_user&.feature_enabled?(:copilot_workspace)
      )

      last_known_stop_notice_text = Codespaces::LastKnownStopNoticeCache.get_text(billable_owner_id: codespace.billable_owner_id)

      control_access :read_codespace,
        codespace:,
        resource: codespace.repository,
        challenge: true,
        forbid: codespace.present?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      refresh_environment_data = params[:refresh] || params[:internal]
      wants_internal_data = params[:internal]

      env_json = get_environment_data(codespace, refresh_environment_data: refresh_environment_data, wants_internal_data: wants_internal_data) if codespace.provisioned?
      data = { codespace: codespace }

      if env_json && env_json["connection"]
        data[:connection] = env_json["connection"]
      end

      if env_json && env_json["container"] && wants_internal_data
        data[:container_id] = env_json["container"]["id"]
      end

      if last_known_stop_notice_text
        data[:last_known_stop_notice] = last_known_stop_notice_text
      end

      if wants_internal_data
        data[:feature_flags] = Codespaces::Vscs.feature_flags(current_user).merge(Codespaces::Jetbrains.feature_flags(current_user))
      end

      deliver :public_codespace_hash, data, private: GitHub.flipper[:codespaces_developer].enabled?(current_user)
    end
  end

  # Update an existing codespace's properties
  patch "/user/codespaces/:codespace_name", operation_id: "codespaces/update-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace!(name: params[:codespace_name])

    control_access :update_codespace,
      codespace:,
      resource: codespace.repository,
      challenge: true,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    # Collapse into one field for ::UpdateSettings, this is legacy support for the old :sku_name param from client.
    data["sku_name"] ||= data.delete("machine")

    Codespaces::UpdateSettings.call(codespace: codespace, **data.symbolize_keys)

    deliver :public_codespace_hash, { codespace: codespace }, private: GitHub.flipper[:codespaces_developer].enabled?(current_user)
  rescue Codespaces::UpdateSettings::FailedToUpdate => e
    deliver_error!(400, message: e.message)
  rescue Codespaces::RateLimitError => e
    deliver_error!(429, message: e.message)
  rescue Codespaces::AsyncOperation::PendingError => e
    deliver_error!(422, message: e.message)
  rescue Codespaces::UpdateSettings::CodespacesStillProvisioningError => e
    deliver_error!(409, messaage: e.message)
  end

  # Create a new codespace
  post "/user/codespaces", operation_id: "codespaces/create-for-authenticated-user" do
    with_aggressive_client_timeouts do
      repo, pull = find_repo_and_pull_request_from_request_body!
      # This sets the repo from the request body as the repo to use for cap filtering in control_access.
      set_current_repo_for_access_control(repo)
      if logged_in?
        billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner
        organization = billable_owner if billable_owner && !billable_owner.user?
      end

      resource = current_user&.feature_enabled?(:codespaces_api_404_when_unauthorized) ? repo : current_user
      control_access :create_codespaces_public,
        resource: resource,
        # Passing in the organization here lets us essentially modify the TFCA used for SAML
        organization: organization,
        repo: repo,
        challenge: true,
        forbid: repo.public?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless ::GitHub.codespaces_enabled?

      # Pull can be nil here which is fine/expected.
      create_codespace(repo: repo, pull: pull, entry_point: :rest_api_codespaces_create_for_authenticated_user)
    end
  end

  # List codespaces for a specific repository
  get "/repositories/:repository_id/codespaces", operation_id: "codespaces/list-in-repository-for-authenticated-user" do
    with_aggressive_client_timeouts do
      repo = find_repo!

      if current_user&.feature_enabled?(:codespaces_api_404_when_unauthorized)
        control_access :list_codespaces_for_repo_public,
          resource: repo,
          repo: repo,
          owner: current_user,
          allow_integrations: false,
          allow_user_via_granular_actor: true
      else
        control_access :read_codespaces_for_repo_public,
          resource: current_user,
          repo: repo,
          forbid: repo.public?,
          allow_integrations: false,
          allow_user_via_granular_actor: true
      end

      deliver_error! 404 unless ::GitHub.codespaces_enabled?

      codespaces, unauthorized_org_ids = find_codespaces(owner: current_user, repository_id: repo.id)

      set_sso_partial_results_header(unauthorized_org_ids) if unauthorized_org_ids.length > 0
      # Preload associations to avoid N+1 queries...
      Codespace.prefill_associations_for_dashboard(codespaces)
      codespaces = paginate_rel(codespaces)

      deliver :public_codespaces_hash, { codespaces: codespaces, total_count: codespaces.total_entries }, private: GitHub.flipper[:codespaces_developer].enabled?(current_user)
    end
  end

  # List devcontainer configurations for a specific repository
  get "/repositories/:repository_id/codespaces/devcontainers", operation_id: "codespaces/list-devcontainers-in-repository-for-authenticated-user" do
    repo = find_repo!

    control_access :read_codespace_repo_metadata_public,
      resource: repo,
      repo: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless ::GitHub.codespaces_enabled?

    ref = params[:ref] || repo.default_branch
    ref_for_oid = Codespaces::GetTargetRef.call(repository: repo, name_or_oid: ref)
    oid = ref_for_oid&.target_oid

    deliver_error! 400, message: INVALID_REF unless oid

    devcontainers = Codespaces::DevContainer.list_dev_containers(repo, oid)
    devcontainers = paginate_rel(devcontainers)

    deliver :devcontainers_hash, { devcontainers: devcontainers, total_count: devcontainers.total_entries }
  end

  # View codespace creation options and defaults for a specific repository.
  get "/repositories/:repository_id/codespaces/new", operation_id: "codespaces/pre-flight-with-repo-for-authenticated-user" do
    repo = find_repo!

    if logged_in?
      billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner

      if billable_owner && !billable_owner.user?
        organization = billable_owner
      end
    end

    resource = current_user&.feature_enabled?(:codespaces_api_404_when_unauthorized) ? repo : current_user

    control_access :create_codespaces_public,
      resource: resource,
      # Passing in the organization here lets us essentially modify the TFCA used for SAML
      organization: organization,
      repo: repo,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error! 403, message: CODESPACE_CANNOT_BE_CREATED_MESSAGE unless billable_owner

    deliver_error! 404 unless ::GitHub.codespaces_enabled?

    region = Codespaces::GetRegionForUser.call(user: current_user, repository: repo, requested_location: params[:location], client_ip: params[:client_ip].presence, client: :api)
    # The fact that this returns a String is a bit annoying but keeps parity with what's being replaced.
    # Unfortunately that means we need to map this back to a Region for now.
    default_location = Codespaces::Locations::Region.find(region).geo.id

    ref = params[:ref] || repo.default_branch
    ref_for_oid = Codespaces::GetTargetRef.call(repository: repo, name_or_oid: ref)
    oid = ref_for_oid&.target_oid
    default_devcontainer_path = Codespaces::DevContainer.get_default_path(repo, oid)

    deliver :codespaces_pre_flight_hash, {
      billable_owner: billable_owner,
      defaults: {
        location: default_location,
        devcontainer_path: default_devcontainer_path,
      },
    }
  end

  get "/repositories/:repository_id/codespaces/permissions_check", operation_id: "codespaces/check-permissions-for-devcontainer" do
    repo = find_repo

    if logged_in?
      billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner

      if billable_owner && !billable_owner.user?
        organization = billable_owner
      end
    end

    control_access :create_codespaces_public,
      resource: repo,
      repo: repo,
      # Passing in the organization here lets us essentially modify the TFCA used for SAML
      organization: organization,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless GitHub.codespaces_enabled?
    deliver_error! 422 unless all_permission_check_params_provided?

    ref = params[:ref]
    devcontainer_filepath = params[:devcontainer_path]
    ref_for_oid = Codespaces::GetTargetRef.call(repository: repo, name_or_oid: ref)
    oid = ref_for_oid&.target_oid

    deliver_error! 422, message: INVALID_REF if oid.nil?

    requested_devcontainer = Codespaces::DevContainer.new(
      repository: repo,
      oid: oid,
      filepath: devcontainer_filepath,
      user: current_user
    )

    deliver :codespaces_permissions_check_hash, {
      accepted: requested_devcontainer.permissions_accepted?
    }
  end

  # Create a new codespace for a specific repository.
  post "/repositories/:repository_id/codespaces", operation_id: "codespaces/create-with-repo-for-authenticated-user" do
    with_aggressive_client_timeouts do
      repo = find_repo!
      if logged_in?
        billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner
        organization = billable_owner if billable_owner && !billable_owner.user?
      end

      resource = current_user&.feature_enabled?(:codespaces_api_404_when_unauthorized) ? repo : current_user

      control_access :create_codespaces_public,
        resource: resource,
        # Passing in the organization here lets us essentially modify the TFCA used for SAML
        organization: organization,
        repo: repo,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless ::GitHub.codespaces_enabled?

      create_codespace(repo: repo, entry_point: :rest_api_codespaces_create_with_repo_for_authenticated_user)
    end
  end

  # Create a new codespace for a specific repo and pull number.
  post "/repositories/:repository_id/pulls/:pull_number/codespaces", operation_id: "codespaces/create-with-pr-for-authenticated-user" do
    with_aggressive_client_timeouts do
      repo, pull = find_repo_and_pull_request!
      if logged_in?
        billable_owner = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync.billable_owner
        organization = billable_owner if billable_owner && !billable_owner.user?
      end

      resource = current_user&.feature_enabled?(:codespaces_api_404_when_unauthorized) ? repo : current_user
      control_access :create_codespaces_public,
        resource: resource,
        # Passing in the organization here lets us essentially modify the TFCA used for SAML
        organization: organization,
        repo: repo,
        challenge: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless ::GitHub.codespaces_enabled?
      create_codespace(repo: repo, pull: pull, entry_point: :rest_api_codespaces_create_with_pr_for_authenticated_user)
    end
  end

  # Deletes a codespace by name
  delete "/user/codespaces/:codespace_name", operation_id: "codespaces/delete-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    # Always include the copilot workspace when deleting a codespace for cleanup purposes
    codespace = find_codespace!(name: params[:codespace_name], include_copilot_workspace: true)

    control_access :update_codespace,
      codespace:,
      resource: codespace.repository,
      challenge: true,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    codespace.deprovision!
    deliver_empty(status: 202)
  end

  # Start an existing codespace
  post "/user/codespaces/:codespace_name/start", operation_id: "codespaces/start-for-authenticated-user" do
    with_aggressive_client_timeouts do
      deliver_error! 404 unless GitHub.codespaces_enabled?

      codespace = find_codespace!(
        name: params[:codespace_name],
        # Always include CW codespaces if the user was able to create them in the first place.
        # If they lost access, the request will 403.
        include_copilot_workspace: true
      )

      control_access :update_codespace_lifecycle_admin,
        codespace:,
        resource: codespace.repository,
        challenge: true,
        forbid: codespace.present?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      start_codespace(codespace, entry_point: :rest_api_codespaces_start_for_authenticated_user)
    end
  end

  # Stop an existing codespace
  post "/user/codespaces/:codespace_name/stop", operation_id: "codespaces/stop-for-authenticated-user" do
    with_aggressive_client_timeouts do
      deliver_error! 404 unless GitHub.codespaces_enabled?

      codespace = find_codespace!(name: params[:codespace_name])

      control_access :update_codespace_lifecycle_admin,
        codespace:,
        resource: codespace.repository,
        challenge: true,
        forbid: codespace.present?,
        allow_integrations: false,
        allow_user_via_granular_actor: true

      stop_codespace(codespace)
    end
  end

  # Create and assign a repository for a previously repo-less codespace.
  post "/user/codespaces/:codespace_name/publish", operation_id: "codespaces/publish-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace!(name: params[:codespace_name])

    control_access :publish_codespace_public,
      resource: codespace,
      challenge: true,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error! 422, message: "This codespace already has an associated repository" unless codespace.unpublished?

    data = receive_with_openapi

    result = Codespaces::PublishToRepository.call(
      codespace:,
      name: data["name"],
      is_private: data["private"]
    )

    if result.success?
      deliver :public_codespace_hash_with_full_repository, { codespace: codespace }, private: GitHub.flipper[:codespaces_developer].enabled?(current_user), status: 201
    else
      deliver_error 422, message: result.reason
    end
  end

  # Fetch available SKUs for a user
  get "/user/codespaces/:codespace_name/machines", operation_id: "codespaces/codespace-machines-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace!(name: params[:codespace_name])

    control_access :read_codespace_metadata,
    codespace:,
    resource: codespace.repository,
    challenge: true,
    forbid: codespace.present?,
    allow_integrations: false,
    allow_user_via_granular_actor: true

    devcontainer = Codespaces::DevContainer.new(repository: codespace.repository, oid: codespace.oid, filepath: codespace.devcontainer_path)
    skus = if codespace.owner.feature_enabled?(:codespaces_allowed_skus_consolidation)
      Codespaces::Skus.allowed_for_display(codespace:, dev_container: devcontainer, location: codespace.location)
    else
      Codespaces::Skus.allowed_skus_for_display(nil, codespace: codespace, dev_container: devcontainer, location: codespace.location)
    end

    deliver :machines_hash, { machines: skus, total_count: skus.count }
  end

  # Export a codespace
  post "/user/codespaces/:codespace_name/exports", operation_id: "codespaces/export-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace!(owner: current_user, name: params[:codespace_name])

    if !codespace.published?
      deliver_error! 422, message: "This codespace must first be published to a repository"
    end

    control_access :update_codespace_lifecycle_admin,
      codespace:,
      resource: codespace.repository,
      challenge: true,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    export_codespace(codespace, entry_point: :rest_api_codespaces_public_export)
  end

  get "/repositories/:repository_id/codespaces/machines", operation_id: "codespaces/repo-machines-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?

    repository = find_repo!

    control_access :read_codespace_repo_metadata_public,
      resource: repository,
      repo: repository,
      forbid: repository.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 403, message: USER_NOT_AUTHORIZED_FOR_VSCS_TARGET_MESSAGE if params.key?("vscs_target") && !GitHub.flipper[:codespaces_developer].enabled?(current_user)

    ref = params[:ref] || repository.default_branch
    ref_for_oid = Codespaces::GetTargetRef.call(repository: repository, name_or_oid: ref)
    if target_oid = ref_for_oid&.target_oid
      devcontainer_path = params[:devcontainer_path].presence
      devcontainer = Codespaces::DevContainer.new(repository: repository, oid: target_oid, filepath: devcontainer_path)
    elsif params[:ref]
      # User tried to specify a ref but it was not valid so we need to let them know...
      deliver_error! 400, message: INVALID_REF
    end

    location_for_skus = Codespaces::GetRegionForUser.call(user: current_user, repository: repository, requested_location: params[:location], client_ip: params[:client_ip], client: :api)

    repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository, ref: ref).sync
    billable_owner = repository_policy.billable_owner

    skus = if repository_policy.repository && !repository_policy.can_attempt_create?
      []
    else
      if GitHub.flipper[:codespaces_allowed_skus_consolidation].enabled?(current_user)
        Codespaces::Skus.allowed_for_display(
          owner: current_user,
          billable_owner: billable_owner,
          repository: repository,
          vscs_target: params[:vscs_target]&.to_sym || Codespaces::Vscs.default_target,
          vscs_target_url: params[:vscs_target_url]&.to_str,
          location: location_for_skus,
          dev_container: devcontainer,
          ref: ref
        )
      else
        Codespaces::Skus.allowed_skus_for_display(
          repository_policy,
          vscs_target: params[:vscs_target]&.to_sym || Codespaces::Vscs.default_target,
          vscs_target_url: params[:vscs_target_url]&.to_str,
          location: location_for_skus,
          dev_container: devcontainer,
          ref: ref
        )
      end
    end

    deliver :machines_hash, { machines: skus, total_count: skus.count }
  end

  # Fetch export details for a codespace
  get "/user/codespaces/:codespace_name/exports/:export_id", operation_id: "codespaces/get-export-details-for-authenticated-user" do
    deliver_error! 404 unless GitHub.codespaces_enabled?
    deliver_error!(404) if params[:export_id] != "latest"

    codespace = find_codespace!(name: params[:codespace_name])

    control_access :read_codespace_lifecycle_admin,
      codespace:,
      resource: codespace.repository,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404) if codespace.export_state == Codespace::EXPORT_STATE_NO_EXPORT_EXISTS

    deliver :export_details_hash, { codespace: codespace }
  end

  protected

  def ensure_async_operation_behavior(operation)
    if response.status == 500 && !request.env["codespaces.async_operation_created"]
      codespaces_automated_testing = begin
        GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
      rescue # rubocop:disable Lint/GenericRescue
        false
      end
      Codespaces::AsyncOperation.report_failure(operation:, codespaces_automated_testing:, failure_reason: request.env["sinatra.error"])
    end
    if @codespace_async_operation && !@codespace_async_operation.ended?
      # If we created the operation successfully but it hasn't been ended lets make sure our response status makes sense
      # and we didn't just miss something that otherwise indicates a failure.
      case response.status
      when 500
        # If we're responding with a 500 but the operation was not already otherwise ended that indicates it was an uncaught
        # exception and we need to mark it as failed to immediately count it against our SLOs rather than waiting for the
        # timeout job to catch it.
        @codespace_async_operation.mark_as_failed(failure_reason: "Uncaught exception")
      when 403, 404, 422
        # If we're responding 403, 404, or 422 that's not an exception and we most likely already created our operation. In that case
        # we just need to mark it as ended here so it doesn't count against our SLOs.
        @codespace_async_operation.mark_as_ended
      end

    end
  end

  private

  def find_repo_and_pull_request!
    repo = find_repo!
    pull = repo.issues.find_by_number(int_id_param!(key: :pull_number)).try(:pull_request) if repo

    if pull.nil? || pull.hide_from_user?(current_user)
      @codespace_async_operation&.mark_as_ended
      deliver_error!(404)
    end

    [repo, pull]
  end

  def find_repo_and_pull_request_from_request_body!
    # We do this again later BUT for POST /user/codespaces we need to pull the repo out of the body BEFORE
    # we call control_access so we can call `set_current_repo_for_access_control`. The other two create
    # endpoints will only hit this once in `create_codespace`.
    data = receive_with_openapi.deep_symbolize_keys

    repo = Repositories::Public.find_active!(data[:repository_id].presence || data[:pull_request][:repository_id])
    pull = repo.issues.find_by(number: data[:pull_request][:pull_request_number])&.pull_request if data[:pull_request].present?

    if pull && pull.hide_from_user?(current_user)
      @codespace_async_operation&.mark_as_ended
      deliver_error!(404)
    end

    [repo, pull]
  end

  def find_codespace!(**args)
    find_codespace(**args) || deliver_error!(404)
  end

  def all_permission_check_params_provided?
    params[:ref].present? && params[:devcontainer_path].present?
  end

  # Saves updated environment data to the passed Codespace instance as a side effect.
  # That still won't include any private data included in the returned env JSON, however.
  def get_environment_data(codespace, environment_data: nil, refresh_environment_data:, wants_internal_data:)
    environment_data ||= codespace.environment_data
    if refresh_environment_data
      ActiveRecord::Base.connected_to(role: :writing) do
        # Fetching the environment below already uses a write connection to update the cached environment data but
        # the call to `codespace.reload` below was outside of that block and thus would not be guaranteed to read that
        # same data from the replica we are connected to by default on this GET request. TBH we probably shouldn't be
        # writing this data in this fashion on a GET request at all but that's some tech debt for another day.
        client = ::Codespaces::VscsClient.for_codespace(codespace)
        env = client.fetch_environment(codespace.guid)
        environment_data = Codespaces::Environment.from_json(env) if env.present?
        codespace.reload # The client fetch saves updated environment_data, but on a separate instance of this same record.
      end
    end
    # No need for additional filtering of internal data if we don't have any so we can bail now.
    return nil unless environment_data.present?
    # If we're not requesting internal data we don't need to do any further checking just return
    # `as_json` which filters out internal data.
    return environment_data.as_json unless wants_internal_data

    # If we want internal data we still need to validate that we're authenticated in a manner that
    # allows access to this data
    if allows_internal_data_access?(codespace)
      # Using `json` passes back the raw environment data unfiltered
      # thus including any internal data fetched above such as `connection`.
      environment_data.json
    else
      # This filters the environment data normally, excluding any non-allow-listed keys
      # such as `connection` that include sensitive details.
      environment_data.as_json
    end
  end

  def allows_internal_data_access?(codespace)
    if current_user.using_auth_via_oauth_application? || # oauth
       current_user.using_personal_access_token? || # PAT
       current_user.using_auth_via_granular_actor? # PATv2
      # We're good if the user is authed via oauth, a PAT, or a PATv2.
      true
    elsif current_user.feature_enabled?(:copilot_workspace_developer)
      # Special case to unblock Copilot workspace developers until they develop an internal app with security.
      true
    else
      # We have a repo-scoped token so we need to do additional checking.
      installation = if current_user.using_auth_via_integration?
        current_user.oauth_access.installation
      else
        current_user.installation
      end
      Api::AccessControl.is_scoped_to_repository?(installation, codespace.repository_id)
    end
  end

  # Creating a codespace allows providing repository and pull request in several ways:
  #   - In the POST body
  #   - As part of the path
  # Because of this we handle finding the repo and pull request in their respective endpoints
  # and pass them in here. The remaining common data is pulled from the POST body using
  # `receive_with_openapi`.
  def create_codespace(repo:, pull: nil, entry_point:)
    repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync
    if current_user.is_enterprise_managed? && !repository_policy.billable_owner
      @codespace_async_operation&.mark_as_ended
      deliver_error!(403, message: Api::Codespaces::Public::EMU_NOT_BILLABLE_FOR_CODESPACES_MESSAGE)
    else
      if repository_policy.has_ip_allowlists?
        @codespace_async_operation&.mark_as_ended
        deliver_error!(403, message: Api::Codespaces::Public::IP_ALLOWLISTS_NOT_SUPPORTED_MESSAGE)
      elsif !repository_policy.changes_would_be_safe?
        @codespace_async_operation&.mark_as_ended
        deliver_error!(403, message: Api::Codespaces::Public::CANT_PUSH_OR_FORK_MESSAGE)
      end
    end

    data = receive_with_openapi.symbolize_keys.slice(:ref, :machine, :location, :geo, :region, :client_ip, :devcontainer_path, :devcontainer_permissions_opt_out, :multi_repo_permissions_opt_out, :working_directory, :idle_timeout_minutes, :vscs_target, :vscs_target_url, :environment_options, :retention_period_minutes, :display_name, :enable_auto_push_on_stop, :copilot_workspace_id, :internal)

    wants_internal_data = !!data.delete(:internal)
    # Set this in case the operation fails validation so we can still ignore non-production targets.
    @codespace_async_operation.vscs_target = data[:vscs_target] || Codespaces::Vscs.default_target if @codespace_async_operation

    # environment_options might include copliotWorkspaceConfig, which contains sensitive data (e.g. JWT). Hence, they should not be logged to telemetry or saved to the database.
    environment_options = (data.delete(:environment_options) || {}).symbolize_keys

    use_copliot_workspace_config_enabled = current_user.feature_enabled?(:copilot_workspace) && current_user.feature_enabled?(:codespaces_using_copilot_workspace_config)

    # In Copilot Workspace, we don't have an easy way to access the feature flags. Hence, it always passes the environment_options.
    if !use_copliot_workspace_config_enabled && environment_options.key?(:copilotWorkspaceConfig)
      environment_options.delete(:copilotWorkspaceConfig)
    end

    if environment_options.present? && !current_user.feature_enabled?(:codespaces_developer)
      # We allow an exception for copilotWorkspaceConfig
      only_copilot_workspace_config_key_present = environment_options.keys == [:copilotWorkspaceConfig]
      unless use_copliot_workspace_config_enabled && only_copilot_workspace_config_key_present
        @codespace_async_operation&.mark_as_ended
        deliver_error!(403, message: USER_NOT_AUTHORIZED_FOR_RAW_ENVIRONMENT_MESSAGE)
      end
    end

    if data.key?(:region) && !current_user.feature_enabled?(:codespaces_developer)
      @codespace_async_operation&.mark_as_ended
      deliver_error!(403, message: USER_NOT_AUTHORIZED_FOR_REGION)
    end

    data[:owner] = current_user
    # In case this was in the path we need to add it to the create data.
    data[:repository_id] = repo.id
    # We only want to set the ref to the default branch if we weren't given a pull request.
    data[:ref] ||= repo.default_branch if !pull
    # Whether this was in the path or the request body we need to add it to the create data at the top level if we have a pull request.
    data[:pull_request_id] = pull.id if pull

    if data[:enable_auto_push_on_stop]
      if repo.public?
        @codespace_async_operation&.mark_as_ended
        deliver_error!(400, message: AUTO_PUSH_NOT_SUPPORTED_FOR_PUBLIC_REPOS_MESSAGE)
      end
      if !repo.pushable_by?(current_user, ref: data[:ref])
        @codespace_async_operation&.mark_as_ended
        deliver_error!(400, message: AUTO_PUSH_NOT_SUPPORTED_FOR_UNPUSHABLE_REPOS_MESSAGE)
      end
    end

    data[:location] = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository: repo,
      requested_region: data.delete(:region) || data[:location],
      requested_geo: data.delete(:geo),
      client_ip: data.delete(:client_ip),
      client: :api,
      vscs_target: data[:vscs_target] || Codespaces::Vscs.default_target
    )

    # devcontainer_permissions_opt_out deprecated in favor of multi_repo_permissions_opt_out
    multi_repo_permissions_opt_out = data.delete(:devcontainer_permissions_opt_out) || data.delete(:multi_repo_permissions_opt_out)

    # check for custom permissions and reject if not consented
    if multi_repo_permissions_opt_out
      begin
        Codespaces::WriteAllowedPermissions.call(
        user: current_user,
        repository: repo,
        opt_out: true,
        repository_permissions: {},
        owner_permissions: {},
        category: "api",
      )
      rescue ActiveRecord::ActiveRecordError => e
        @codespace_async_operation&.mark_as_ended
        GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:api", "error_type:#{e.class.name}"])
        deliver_error!(400, message: "There was an unexpected problem removing access to other repositories you have previously allowed for codespaces using this repository. Please contact support.")
      rescue Codespaces::Error => e
        @codespace_async_operation&.mark_as_ended
        GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:api", "error_type:#{e.class.name}"])
        deliver_error!(400, message: e.message)
      rescue => e # rubocop:disable Lint/GenericRescue
        @codespace_async_operation&.mark_as_failed(failure_reason: e)
        raise
      end
    else
      devcontainer_path = data[:devcontainer_path].presence
      ref = data[:ref] || repo.default_branch

      oid = Codespaces::GetTargetRef.call(repository: repo, name_or_oid: ref)&.target_oid

      if !oid
        @codespace_async_operation&.mark_as_ended
        deliver_error! 400, message: INVALID_REF
      end

      devcontainer = Codespaces::DevContainer.new(
        repository: repo,
        oid: oid,
        filepath: devcontainer_path,
        user: current_user
      )

      if devcontainer.permissions_need_allowance?
        @codespace_async_operation&.mark_as_ended
        return deliver :accept_permissions_hash, { ref: ref, devcontainer: devcontainer }, status: 401
      end
    end

    # We have to move working_directory, idle_timeout, devcontainer_path, and enable_auto_push_on_stop into environment_options to pass it through properly to VSCS.
    environment_options[:workingDirectory] = data.delete(:working_directory) if data[:working_directory]

    idle_timeout = data.delete(:idle_timeout_minutes) if data[:idle_timeout_minutes]

    if idle_timeout
      settings = Codespaces::Settings.new(user: current_user)
      settings.default_idle_timeout = idle_timeout

      if !settings.valid?
        @codespace_async_operation&.mark_as_ended
        deliver_error!(400, message: "idle_timeout_minutes #{settings.errors[:default_idle_timeout]&.first}")
      end

      environment_options[:requestedIdleTimeoutMinutes] = idle_timeout
    end

    data.delete(:devcontainer_path) if data[:devcontainer_path] == "default"
    environment_options[:devcontainerPath] = data[:devcontainer_path] if data[:devcontainer_path]

    environment_options[:enableAutoPushOnStop] = data.delete(:enable_auto_push_on_stop) if data[:enable_auto_push_on_stop]
    environment_options[:copilot_workspace_id] = data[:copilot_workspace_id] if data[:copilot_workspace_id]
    result = ::Codespaces::Create.call(
      attributes: data.compact, environment_options: environment_options, cap_filter: cap_filter, entry_point: entry_point, operation: @codespace_async_operation
    )

    status_code = result.provisioned? ? 201 : 202

    if GitHub.flipper[:codespaces_api_internal_connect_on_create].enabled?(current_user)

      codespace = result.codespace

      env_json = get_environment_data(codespace, environment_data: result.env, wants_internal_data: wants_internal_data, refresh_environment_data: false)

      data = { codespace: codespace }

      if wants_internal_data && env_json && env_json["connection"]
        data[:connection] = env_json["connection"]
      end

      deliver :public_codespace_hash, data, status: status_code, private: current_user.feature_enabled?(:codespaces_developer)
    else
      deliver :public_codespace_hash, { codespace: result.codespace }, status: status_code, private: current_user.feature_enabled?(:codespaces_developer)
    end
  rescue ActiveModel::ValidationError => e
    @codespace_async_operation&.mark_as_ended
    status = 400
    if e.model.errors.include?(:usage)
      status = 402
    end
    deliver_error! status, message: e.model.errors.full_messages.join(", ")
  rescue ActiveRecord::RecordInvalid => e
    @codespace_async_operation&.mark_as_ended
    status = 400
    if e.record.errors.include?(:usage)
      status = 402
    end
    deliver_error! status, message: e.record.errors.full_messages.join(", ")
  rescue Codespaces::Client::BadResponseError => e
    if e.unprocessable_entity?
      @codespace_async_operation&.mark_as_ended
    else
      @codespace_async_operation&.mark_as_failed(failure_reason: e.status)
      Codespaces::ErrorReporter.report(e)
    end
    deliver_error! e.status, message: e.message
  rescue Codespaces::CopilotWorkspaceFeatureDisabledError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 403, message: e.message
  rescue Codespaces::Plan::PlanNotFoundForLocation => e
    @codespace_async_operation&.mark_as_failed(failure_reason: e)
    Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
    deliver_error! 400, message: INVALID_LOCATION_FOR_VSCS_TARGET_MESSAGE
  rescue Codespaces::VscsClient::SecretDataTooLarge => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 422, message: e.message
  rescue Codespaces::ConcurrencyLimitError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::CopilotWorkspaceConcurrencyLimitError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::RateLimitError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 429, message: e.message
  rescue Codespaces::DevContainer::ReadError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::DevContainer::ParseError
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: "Provided devcontainer.json cannot be parsed to valid JSON"
  rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
    @codespace_async_operation&.mark_as_failed(failure_reason: e)
    Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
    deliver_error! 400, message: e.message
  rescue Codespaces::Locations::Region::UnavailableError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 503, message: e.message
  rescue Codespaces::Locations::Region::InvalidError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::Locations::Geo::InvalidError => e
    @codespace_async_operation&.mark_as_ended
    deliver_error! 400, message: e.message
  rescue Codespaces::Tokens::Error => e
    if e.message.include?("repository_not_found")
      @codespace_async_operation&.mark_as_ended
      deliver_error! 403, message: "The repository could not be found."
    else
      @codespace_async_operation&.mark_as_failed(failure_reason: e)
      deliver_error! 400, message: e.message
    end
  rescue => e # rubocop:disable Lint/GenericRescue
    @codespace_async_operation&.mark_as_failed(failure_reason: e)
    raise
  end
end
