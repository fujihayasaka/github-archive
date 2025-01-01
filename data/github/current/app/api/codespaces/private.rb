# typed: true
# frozen_string_literal: true

class Api::Codespaces::Private < Api::Codespaces
  CODESPACE_MUST_BE_PROVISIONED_MESSAGE = "codespace must be provisioned"

  patch "/vscs_internal/user-settings", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    control_access :codespace_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    settings = Codespaces::Settings.for_user(current_user)
    data = receive_with_schema("codespace", "codespaces-user-settings-update", expected_type: Hash)
    settings.write_attributes(data)
    if settings.valid?
      settings.save
      deliver_raw(settings.changes)
    else
      deliver_error 422, errors: settings.errors.full_messages
    end
  end

  post "/vscs_internal/user/:user_id/codespaces/:name/token", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    owner = find_user!

    codespace = find_codespace(
      owner: owner,
      name: params[:name],
      include_copilot_workspace: owner.feature_enabled?(:copilot_workspace)
    )

    control_access :write_codespace,
      resource: codespace,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    set_exception_context(codespace)

    deliver_error! 402 unless codespace.plan.nil? ||
        ::Codespaces::AccessChecker.from_codespace(codespace)
          .allowed?(sku_name: codespace.sku_name, dev_container: codespace.dev_container)

    # require a provisioned codespace so we can scope the token to a single
    # environment https://github.com/github/codespaces/issues/310.
    unless codespace.provisioned?
      deliver_error! 422, message: CODESPACE_MUST_BE_PROVISIONED_MESSAGE
    end

    data = receive_with_schema("codespace", "mint-repository-token")

    token = Codespaces::FetchCascadeToken.call(codespace: codespace, ignore_cache: true)

    response = { token: token }

    if data["mint_repository_token"] && current_user.using_auth_via_oauth_application?
      repository_token = Codespaces::Tokens.mint_github_token(current_user, codespace, entry_point: :rest_api_codespaces_private_mint_repository_token)
      response["repository_token"] = repository_token
    end

    codespace.mark_used!

    deliver_raw(response)
  end

  post "/vscs_internal/user/:user_id/codespaces/:name/fork_repo", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    owner = find_user!
    codespace = find_codespace(owner: owner, name: params[:name])

    control_access :write_codespace,
      resource: codespace,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_json(request.body.read)
    if data.is_a? Hash
      branch = data["branch"]
    end

    begin
      forked_repo, ref = Codespaces::ForkRepo.call(codespace, branch, entry_point: :rest_api_vscs_internal_fork_repo)

      deliver :codespace_fork_repo_result, { forked_repo: forked_repo, ref: ref }, { global_id_selection: global_id_selection }
    rescue Codespaces::ForkRepo::UnforkableRepository, Codespaces::ForkRepo::UserOwnsParentRepository => e
      deliver_error! 400, message: e.message
    end
  end

  post "/vscs_internal/commit/sign", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    control_access :codespace_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_schema("codespace", "codespaces-commit-sign", expected_type: Hash)

    signature_request = Codespaces::GpgSignatureRequest.new(
      current_user:    current_user,
      message:         data["message"],
      codespace_token: data["codespace_token"]
    )

    if signature = signature_request.sign
      deliver_raw({ signature: signature })
    else
      deliver_error! 403, message: signature_request.errors.full_messages.join(", ")
    end
  end

  get "/vscs_internal/user/:user_id/repo/:repository_id/fork_required", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    user = find_user!
    repo = get_repo_if_accessible_by_user(params[:repository_id], user: user)

    deliver_error! 404 unless repo

    control_access :list_codespaces,
      resource: user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    report = ::Codespaces::ForkabilityReport.new(user: user, repo: repo)
    deliver_raw(report)
  end

  post "/vscs_internal/codespaces/:name/archive", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace(name: params[:name])
    deliver_error! 404 unless codespace

    control_access :write_codespace,
      resource: codespace,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    client = Codespaces::VscsClient.for_codespace(codespace)
    response = client.archive_environment(codespace.guid)
    deliver_raw response,
      status: 200
  end

  get "/vscs_internal/codespaces/:name/archive", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?

    codespace = find_codespace(name: params[:name])
    deliver_error! 404 unless codespace

    control_access :write_codespace,
      resource: codespace,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    client = Codespaces::VscsClient.for_codespace(codespace)
    response = client.get_archive_environment_status(codespace.guid)
    deliver_raw response,
      status: 200
  end

  get "/codespaces_internal/supported_versions/:client", operation_id: :internal do
    @route_owner = "@github/codespaces"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    response = Codespaces::VersioningPolicy.codespaces_clients_supported(params[:client])

    deliver_error! 404 if response.nil?
    deliver_raw response, status: 200
  end

  get "/codespaces_internal/supported_versions", operation_id: :internal do
    @route_owner = "@github/codespaces"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    response = Codespaces::VersioningPolicy.codespaces_clients_supported(nil)
    deliver_raw response, status: 200
  end

  get "/codespaces_internal/analytics_tracking_id", operation_id: :internal do
    @route_owner = "@github/codespaces"
    deliver_error! 404 unless GitHub.codespaces_enabled?
    control_access :codespace_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_raw({ analytics_tracking_id: current_user.analytics_tracking_id }, status: 200)
  end

  # Validate a user's token with a minimum of time spent.
  get "/vscs_internal/validate_lwe_user", operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/codespaces"
    control_access :lightweight_web_editor_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed internal call, disabled for speed

    deliver_raw({ valid_token: true }, status: 200)
  end

  post "/codespaces_internal/:name/ports/token", operation_id: :internal do
    @route_owner = "@github/codespaces"

    deliver_error! 404 unless GitHub.codespaces_enabled?

    body = receive(Hash)

    deliver_error! 400, message: "port parameter is missing" unless port = body["port"]&.to_i
    deliver_error! 400, message: "port parameter is invalid" unless port > 0

    codespace = Codespace.find_by(name: params[:name])
    deliver_error! 404 unless codespace

    control_access :read_codespaces_for_repo_public,
      resource: T.must(codespace).repository,
      repo: T.must(codespace).repository,
      forbid: codespace.present?,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    token, visibility = Codespaces::FetchBasisTokenAndVisibility.call(codespace:, port:)
    deliver_error! 404 unless token && visibility

    authorized, _ = Codespaces::AuthorizePortForwarding.call(
      user: current_user,
      codespace:,
      visibility:,
    )
    deliver_error! 404 unless authorized

    skip_anti_phishing = current_user == T.must(codespace).owner

    deliver_raw({ token:, skipAntiPhishing: skip_anti_phishing })
  end

  private

  def get_repo_if_accessible_by_user(repository_id, user:)
    Repository
      .public_or_accessible_by(user)
      .find_by(id: repository_id)
  end
end
