# typed: true
# frozen_string_literal: true

class Api::Copilot < Api::App
  map_to_service :"copilot-access", only: [ # rubocop:todo GitHub/MapToService
    "GET /copilot_internal/user",
    "POST /copilot_internal/notification",
    "POST /copilot_internal/subscribe_limited_user",
  ]

  map_to_service :"copilot-auth-and-limits", only: [ # rubocop:todo GitHub/MapToService
    "GET /copilot_internal/v2/token",
  ]

  include FeatureFlagHelper
  include Scientist
  include BlackbirdIndexHelper
  include Copilot::ContentExclusion::ApiHelper
  include Copilot::Mcp::RegistryApiHelper

  # Tenant slugs for the Microsoft-operated Proxima stamps (msft.ghe.com and
  # microsoft.ghe.com). Every user on these stamps is considered staff.
  MICROSOFT_PROXIMA_STAMP_SLUGS = T.let(%w[msft microsoft].freeze, T::Array[String])

  # Slug of the Microsoft enterprise managed users (EMU) enterprise on dotcom.
  MICROSOFT_EMU_ENTERPRISE_SLUG = T.let("microsoft", String)

  # Stamp-name prefix for the Microsoft-internal staff Proxima stamps (e.g.
  # staff-wus2-01). Every user on a stamp with this prefix is considered staff.
  STAFF_PROXIMA_STAMP_PREFIX = T.let("staff-", String)

  get "/copilot_internal/v2/token", operation_id: :internal do
    @route_owner = "@github/copilot-auth-and-limits"

    control_access :generate_copilot_token,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)
    headers = copilot_headers(env)

    authorizer = Copilot::Authorizer.new(
      copilot_user,
      GitHub.context,
      headers,
      include_snippy: true,
    )

    if GitHub.multi_tenant_enterprise? && authorizer.has_cfi_access?
      deliver_error!(403, message: "Rate Limit Exceeded. #{Api::App::RateLimitDependency::LIMITING_TOS_MESSAGE}")
    end

    if authorizer.access_allowed?
      # If we have any payment method auth checks that are pending_token, we need to flip those to active
      if current_user.feature_flag_enabled?(:copilot_business_secondary_auth_check, default: false) && copilot_user.has_pending_auth_checks?
        ActiveRecord::Base.connected_to(role: :writing) do
          copilot_user.activate_pending_auth_checks!
        end
      end

      # if this is a Seat Assignment, we need to make sure to convert it to Seats
      if authorizer.access_type.to_s.include?("SEAT_ASSIGNMENT")
        GitHub.logger.info("Triggering seat assignment conversion", "gh.user.id" => current_user.id)
        Copilot::SeatManagement::AccessSeatAssignmentConversionJob.perform_later(
          user_id: current_user.id,
          headers: headers,
        )
      end

      # moving the envelope down here because we want to check the ip first up there
      envelope = Copilot::Envelope.new(authorizer, headers, cap_filter)
      envelope.instrument_token_generation(headers)
      deliver_raw(envelope.envelope.sort.to_h)
    else
      # moving the envelope down here because we want to check the ip first up there
      envelope = Copilot::Envelope.new(authorizer, headers)
      envelope.instrument_token_failure(authorizer.reason, headers)

      # Ensure the limiting Terms of Service message is always appended to token error responses
      envelope_hash = envelope.envelope
      msg = envelope_hash[:message] || envelope_hash["message"] || ""
      tos = Api::App::RateLimitDependency::LIMITING_TOS_MESSAGE

      unless msg.include?(tos)
        updated_msg = "#{msg}. #{tos}".strip
        # Preserve existing key type (Symbol/String) used by the envelope
        if envelope_hash.key?(:message)
          envelope_hash[:message] = updated_msg
        else
          envelope_hash["message"] = updated_msg
        end
      end

      halt deliver_raw(envelope_hash.sort.to_h, status: 403)
    end
  rescue StandardError => e
    copilot_error = Copilot::Errors::TokenFailureError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
    Copilot::Instrumenter.instrument_token_failed(Copilot::User.new(current_user), "server_error", copilot_headers(env))

    error_envelope = {
      message: "Resource not accessible by integration. #{Api::App::RateLimitDependency::LIMITING_TOS_MESSAGE}",
      error_details: {
        url: Copilot::Envelope::SUPPORT_PAGE,
        message: "Contact Support.",
        title: "Contact Support",
        notification_id: "server_error"
      }
    }
    halt deliver_raw(error_envelope, status: 403)
  end

  # This endpoint is for the editor to acknowledge that the user has seen the notification
  post "/copilot_internal/notification", operation_id: :internal, read_from_replicas: true do
    @route_owner = "@github/heart-services"

    # This is the only check we're doing - just making sure they
    # are coming from the IDE
    #
    # This is a different name in case we want to check this differently
    control_access :copilot_notification,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive(Hash)
    notification_id = data.fetch("notification_id", nil)

    deliver_error!(404) unless notification_id.present?

    copilot_user = Copilot::User.new(current_user)
    acknowledged = copilot_user.acknowledge_notification(notification_id, user_agent: user_agent.to_s)

    deliver_raw({ notification_id: notification_id, acknowledged: acknowledged })
  end

  # This endpoint is for the editor to "subscribe" the user to our limited user sku
  post "/copilot_internal/subscribe_limited_user", operation_id: :internal, read_from_replicas: true do
    @route_owner = "@github/heart-services"

    deliver_error!(
      422,
      message: "Please contact your enterprise admin to enable your managed account for Copilot Business."
    ) if current_user&.is_enterprise_managed?

    deliver_error!(404) if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    # Authorization check for subscribe_limited_user:
    # - When copilot_subscribe_limited_user_expanded_auth is OFF: requires app with generate_copilot_cdn_token capability
    # - When ON: requires app with subscribe_limited_user capability OR v2 PAT with user_copilot_requests permission

    control_access :copilot_subscribe_limited_user_access,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # for our development stuff now, we are not REQUIRING this but we will use the
    # data passed like this:
    # {
    #   "public_code_suggestions" => "disabled",
    #   "restricted_telemetry" => "disabled",
    # }
    data = receive(Hash, required: false)

    # public code suggestions are DISABLED by default, but we can enable them
    public_code_suggestions = data.fetch("public_code_suggestions", "disabled")
    # restricted_telemetry is DISABLED by default, but we can enable them
    restricted_telemetry = data.fetch("restricted_telemetry", "disabled")

    GitHub.logger.info "Received #{data}"

    headers = copilot_headers(env)

    copilot_user = Copilot::User.new(current_user)
    restrictor = Copilot::Authorization::TradeRestrictor.new(copilot_user)

    if GitHub.context.present? && restrictor.restricted?(GitHub.context, headers)
      GitHub.logger.info "User is trade restricted"
      # they are restricted, let's just return that
      deliver_error!(403, message: "User is trade restricted")
    end

    # if they are already subscribed, let's just return that
    limited_user = Copilot::LimitedUser.subscribed.find_by(user_id: current_user.id)

    if limited_user.present?
      # they are already subscribed, let's just return that
      GitHub.logger.info "User is already subscribed"

      response = {
        subscribed: false, # setting this so the IDE knows that the user was already subscribed
        public_code_suggestions: copilot_user.allow_public_code_suggestions? ? "enabled" : "disabled",
        restricted_telemetry: copilot_user.telemetry_enabled? ? "enabled" : "disabled",
        limited_user_subscribed_day: limited_user.subscribed_at.day.to_s,
        limited_user_reset_date: limited_user.reset_date
      }

      halt deliver_raw(response)
    end

    # subscribe them to the limited user sku
    subscribed = copilot_user.subscribe_limited_user

    if subscribed.ok?
      Copilot::Instrumenter.instrument_signup_limited_subscription_created(
        copilot_user,
        utm_query_params: {
          utm_source: headers[:editor_version].to_s,
          utm_medium: "IDE",
          },
      )

      case public_code_suggestions
      when "enabled"
        copilot_user.allow_public_code_suggestions!
      when "disabled"
        copilot_user.block_public_code_suggestions!
      else
        GitHub.logger.info "Unknown public_code_suggestions value: #{public_code_suggestions}"
        copilot_user.allow_public_code_suggestions!
        public_code_suggestions = "enabled"
      end

      if copilot_user.feature_flag_enabled?(:copilot_preserve_telemetry_on_free_signup, default: false)
        # We do not want to enable restricted telemetry when signing up for Copilot Free. We now allow this setting
        # to be modified without a Copilot license, and we want to make sure the user preference is respected.
        # https://github.com/github/Copilot-Controls/issues/925
        if restricted_telemetry == "disabled"
          copilot_user.disable_telemetry!
        end
      else
        case restricted_telemetry
        when "enabled"
          copilot_user.enable_telemetry!
        when "disabled"
          copilot_user.disable_telemetry!
        else
          GitHub.logger.info "Unknown restricted_telemetry value: #{restricted_telemetry}"
          copilot_user.enable_telemetry!
        end
      end

      limited_user = copilot_user.limited_user

      # Force cache rebuild after all settings are applied so downstream consumers
      # see the new subscription and preferences immediately
      Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "signup_free")

      response = {
        subscribed: true,
        public_code_suggestions: public_code_suggestions,
        restricted_telemetry: copilot_user.telemetry_enabled? ? "enabled" : "disabled",
      }
      if limited_user.present?
        response[:limited_user_subscribed_day] = limited_user.subscribed_at.day
        response[:limited_user_reset_date] = limited_user.reset_date
      end
      deliver_raw(response)
    else
      GitHub.logger.error("Error subscribing user: #{subscribed.error}", { user_id: current_user.id })
      deliver_error!(
        422,
        message: subscribed.error.message,
      )
    end
  end

  post "/copilot_internal/repository_check", operation_id: :internal do
    @route_owner = "@github/copilot"

    control_access :copilot_repository_check,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404)
  end

  # This endpoint is to check a user's Copilot license/subscription status
  get "/copilot_internal/user", operation_id: :internal do
    @route_owner = "@github/heart-services"
    deliver_error!(404) if GitHub.enterprise?

    control_access :copilot_user_status,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)
    authorizer = copilot_user.copilot_authorizer_object_no_snippy

    headers = copilot_headers(env)

    organizations = authorizer.organizations
    GitHub::PrefillAssociations.prefill_associations(organizations.map(&:organization_object), [:profile])

    organization_list = organizations.map do |org|
      { login: org.display_login, name: org.display_name }
    end

    plan = copilot_user.copilot_plan
    plan = "individual_edu" if copilot_user.has_educational_access? && FeatureFlag.vexi.enabled?(:copilot_user_api_individual_edu_plan, current_user, default: false)
    plan = "individual_pro" if copilot_user.has_pro_plus_access?
    plan = "individual_max" if copilot_user.has_max_access? && FeatureFlag.vexi.enabled?(:copilot_max_sku_signup, current_user, default: false)

    restricted_telemetry = !GitHub.multi_tenant_enterprise? && copilot_user.telemetry_enabled?
    mcp_enabled = copilot_user.mcp_enabled?
    all_policies = copilot_user.all_policies
    cloud_session_storage_enabled = copilot_user.cli_cloud_session_storage_enabled?
    cloud_session_storage_value = cloud_session_storage_enabled ? "enabled" : "disabled"
    cli_remote_control_value = Copilot::Policies::CliRemoteControl.effective_value(copilot_user, all_policies)
    cli_remote_control_enabled = cli_remote_control_value == "enabled"

    response = {
      login: current_user.display_login,
      access_type_sku: authorizer.access_type_sku,
      analytics_tracking_id: current_user.analytics_tracking_id,
      assigned_date: copilot_user.assigned_date,
      can_signup_for_limited: copilot_user.can_signup_for_limited?,
      chat_enabled: copilot_user.chat_enabled?,
      cli_enabled: copilot_user.cli_enabled?,
      copilotignore_enabled: copilot_user.copilot_content_exclusion_enabled?,
      copilot_plan: plan,
      editor_preview_features_enabled: copilot_user.editor_preview_features_enabled?,
      is_mcp_enabled: mcp_enabled,
      is_staff: staff?(copilot_user),
      organization_login_list: authorizer.organization_login_list,
      organization_list: organization_list,
      restricted_telemetry: restricted_telemetry,
      cli_remote_control_enabled: cli_remote_control_enabled,
    }

    response[:cloud_session_storage_enabled] = cloud_session_storage_enabled
    # Policy details are read-only attribution derived from all_policies. Gate and
    # observe the extra Ruby work during rollout, and keep attribution failures
    # from breaking the rest of the user response.
    if authorizer.access_allowed? && current_user.feature_flag_enabled?(:copilot_cli_policy_details, default: false)
      policy_details = copilot_cli_policy_details_with_observability(
        copilot_user: copilot_user,
        all_policies: all_policies,
        cli_remote_control_value: cli_remote_control_value,
        cloud_session_storage_value: cloud_session_storage_value,
      )
      response[:copilot_policy_details] = policy_details if policy_details.present?
    end

    if FeatureFlag.vexi.enabled?(:copilot_user_status_endpoints, current_user, default: false)
      sku_isolation = Copilot::SKUIsolation.for_user(current_user)
      response["endpoints"] = sku_isolation.endpoints
    end

    if FeatureFlag.vexi.enabled?(:copilot_user_can_upgrade_plan_field, current_user, default: false)
      response[:can_upgrade_plan] = copilot_user.can_upgrade_plan?
    end

    if copilot_user.codex_agent_enabled?
      # For now, avoid exposing the codex_agent_enabled field to users who don't have access.
      response["codex_agent_enabled"] = true
    end

    if authorizer.access_type_sku == "free_limited_copilot"
      limited_user = Copilot::LimitedUser.for_subscribed_user(current_user)
      if limited_user.present?
        if limited_user.use_token_based_billing?
          response["quota_snapshots"] = limited_user.quota_snapshots
          response["token_based_billing"] = limited_user.use_token_based_billing?
          tbb_reset_date = Time.current.utc.next_month.beginning_of_month
          response["quota_reset_date"] = tbb_reset_date.to_date.to_s
          if FeatureFlag.vexi.enabled?(:copilot_quota_reset_date_utc, current_user, default: false)
            response["quota_reset_date_utc"] = tbb_reset_date
          end
        else
          response["limited_user_quotas"] = limited_user.quotas_remaining
          # we want to show the day of the month that they subscribed
          response["limited_user_subscribed_day"] = limited_user.subscribed_at.day
          response["limited_user_reset_date"] = limited_user.reset_date
          response["monthly_quotas"] = Copilot::Quotas.monthly_quotas
        end
      end
    end

    if copilot_user.consumptive_user?
      response["quota_reset_date"] = copilot_user.quota_reset_date_utc.to_date.to_s
      response["quota_snapshots"] = copilot_user.quota_snapshots
      if FeatureFlag.vexi.enabled?(:copilot_quota_reset_date_utc, current_user, default: false)
        response["quota_reset_date_utc"] = copilot_user.quota_reset_date_utc
      end
      if copilot_user.use_token_based_billing?
        response["token_based_billing"] = true
      end
    end

    Copilot::Instrumenter.instrument_internal_user_called(
      copilot_user,
      authorizer.access_type,
      mcp_enabled,
      headers,
    ) if authorizer.access_allowed?

    deliver_raw(response)
  end

  get "/copilot_internal/org_custom_instructions/:org_login", operation_id: :internal do
    @route_owner = "@github/copilot-dotcom-chat"

    # Validate org login format first
    deliver_error! 422 unless User::LOGIN_REGEX =~ params[:org_login]

    org = Organization.find_by_login(params[:org_login]) || deliver_error!(404)

    # Authorization check first (handles SAML/SSO/CAP, rejects bots)
    control_access :copilot_org_custom_instructions,
      # When we pass in an organization as the resource, control_access automatically checks that the user is a member of the org.
      resource: org,
      # Do not allow bots since this endpoint is internal to just the GitHub app used by IDEs.
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Make sure user has cfb access (cached via Public::User settings cache).
    # has_cb_access? is populated from Copilot::User#has_cfb_access? which includes both
    # CFB and CFE access types, so it's equivalent to Authorizer#has_cfb_access?.
    if FeatureFlag.vexi.enabled?(:copilot_org_instructions_cached_user, current_user, default: false)
      copilot_user = Copilot::Public::User.for(current_user)
      deliver_error!(404) unless copilot_user.has_cb_access?
    else
      copilot_user = Copilot::User.new(current_user)
      authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)
      deliver_error!(404) unless authorizer.has_cfb_access?
    end

    instructions = Copilot::CustomInstructions.for_organization(org)

    deliver_raw({ prompt: instructions&.prompt })
  rescue StandardError => e
    copilot_error = Copilot::Errors::OrgCustomInstructionError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: current_user)
    deliver_error!(500)
  end

  get "/copilot_internal/content_exclusion", operation_id: :internal do
    @route_owner = "@github/copilot-controls"

    control_access :copilot_content_exclusion,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)

    unless copilot_user.copilot_content_exclusion_enabled?
      GitHub.logger.info("Unexpected request for content exclusion rules", {
        "code.function" => "get_content_exclusion",
        "gh.org.list.id" => copilot_user.copilot_organizations.pluck(:id),
      })
      deliver_error!(404)
    end

    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)

    deliver_error!(404) unless authorizer.has_cfb_access?

    url_strings = T.let(params.fetch("repos", "").split(",").map(&:strip), T::Array[String])
    scope = params.fetch("scope", Copilot::ContentExclusion::Document::Scope::REPO)

    url_results = get_content_exclusion_rules(copilot_user, scope, url_strings)

    deliver_raw url_results
  rescue StandardError => e
    copilot_error = Copilot::Errors::ContentExclusionError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
    deliver_error!(404)
  end

  # TODO: This endpoint is deprecated: use `/repositories/:repository_id/copilot_internal/embeddings_index` instead.
  get "/copilot_internal/check_indexing_status", operation_id: :internal do
    @route_owner = "@github/code-search-reviewers"

    nwo = params[:nwo] || ""
    repo = Repository.nwo(nwo)

    record_or_404(repo)

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cir = CopilotIndexedRepositories.find_by(repository: repo.id)
    code_status = if cir.nil?
      :not_indexed
    else
      cir.semantic_code_search_ok? ? :indexed : :indexing
    end

    deliver_raw({
      code_status: code_status,
      docs_status: code_status, # NB: `docs_status` is deprecated
      can_index: can_index_embeddings_status(current_user, repo)
    })
  end

  get "/copilot_internal/workspace", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # let's check the HMAC they sent us. it should be an HMAC signature with
    # our request path and the username
    received_hmac = env[REQUEST_HMAC_HEADER]
    result, _ = self.class.verify_request_hmac(received_hmac)
    if result == :success
      GitHub.dogstats.increment("copilot.workspace.success")
      response = {
        spark_enabled: current_user.feature_flag_enabled?(:github_spark, default: false),
      }
      deliver_raw(response)
    else
      GitHub.dogstats.increment("copilot.workspace.failure")
      GitHub.logger.error("HMAC signature was invalid")
      deliver_error!(401, message: result)
    end
  end

  patch "/copilot_internal/chat_attachments/:attachment_id", operation_id: :internal, read_from_replicas: true do
    @route_owner = "@github/copilot-api"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::Public::User.for(current_user)
    deliver_error! 404 unless copilot_user.has_copilot_access?

    attachment = Copilot::ChatAttachment.uploaded_by(current_user).where(
      id: params[:attachment_id],
    ).first

    deliver_error! 404 if attachment.nil?

    attachment = T.must(attachment)
    data = receive(Hash)

    if data["state"] == "uploaded"
      saved = with_write(clusters: ApplicationRecord::Copilot) { attachment.track_uploaded }

      if saved
        deliver_raw({
          url: attachment.permalink
        }, status: 201)
      else
        deliver_error! 422, errors: attachment.errors
      end
    else
      deliver_error! 422, message: "Only uploaded chat attachments states can be changed."
    end
  end

  get "/copilot_internal/repository_search", operation_id: :internal do
    @route_owner = "@github/copilot-api"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::Public::User.new(current_user)
    deliver_error! 404 unless copilot_user.has_copilot_access?

    query = params[:q].to_s.strip
    limit = (params[:limit]&.to_i || 10).clamp(1, 100)

    repositories = if params[:type] == "search"
      include_forks = params[:include_forks] == "true"

      Copilot::Chat::RepositorySearch.new(
        user: current_user,
        user_session: nil,
        remote_ip: remote_ip,
        cap_filter: cap_filter,
      ).search(
        query: query,
        limit: limit,
        include_forks: include_forks,
      )
    else
      top_repos = TopRepositories.for(
        viewer: current_user,
        since: 1.year.ago,
        cap_filter: cap_filter
      )
      if query.present?
        top_repos = top_repos.limit(UserRanked::Cache::CACHE_LIMIT).to_a
        filter_top_repos(query, top_repos, current_user).first(limit)
      else
        top_repos.limit(limit).to_a
      end
    end

    deliver_raw({
      repositories: repositories.map do |repo|
        repo_owner = T.must(repo.owner)
        {
          id: repo.id,
          name: repo.name,
          name_with_owner: repo.name_with_display_owner,
          owner_login: repo_owner.display_login,
          owner_type: repo_owner.is_a?(Organization) ? "Organization" : "User",
          owner_avatar_url: repo_owner.primary_avatar_url,
          is_private: repo.private?,
          visibility: repo.visibility,
        }
      end,
    })
  end

  # Returns the merge-readiness ("mergebox") summary for a single pull request
  # with ETag / 304 support, so the GitHub Copilot desktop app can replace its
  # per-PR GraphQL polling with a cheap, cacheable REST call. Internal only.
  #
  # The :repository_id segment accepts either a numeric repository id or, via the
  # router's /repos/:owner/:repo rewrite, a name-with-owner.
  get "/repositories/:repository_id/copilot_internal/pulls/:pull_number/merge_status", operation_id: :internal do
    @route_owner = "@github/copilot-api"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::Public::User.new(current_user)
    deliver_error! 404 unless copilot_user.has_copilot_access?

    repository = T.cast(find_repo!, ::Repository)
    deliver_error! 404 unless repository.pullable_by?(current_user)

    pull = begin
      T.cast(
        PullRequests::PullRequestAccessor.new.by_number(
          repository_id: T.must(repository.id),
          number: params[:pull_number].to_i,
        ),
        ::PullRequest,
      )
    rescue GH::Errors::ObjectNotFound
      deliver_error!(404)
    end

    deliver_error!(404) if pull.hide_from_user?(current_user)
    deliver_error!(404) if pull.archived_and_hidden_from?(current_user)
    deliver_error!(404) if pull.killed_and_hidden_from?(current_user)

    body = Copilot::PullRequestMergeStatusResponse.new(
      pull_request: pull,
      repository: repository,
      viewer: current_user,
    ).payload

    # deliver_raw derives an ETag from the response body and lets Sinatra answer
    # conditional requests with 304, so the desktop app can poll cheaply.
    deliver_raw(body, max_age: 60)
  end

  get "/copilot/mcp_registry", operation_id: :internal do
    @route_owner = "@github/copilot-ecosystem"

    control_access :copilot_mcp_registry,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)

    unless copilot_user.mcp_enabled?
      GitHub.logger.info("Request made by user without access to MCP", {
        "code.function" => "get_mcp_registry",
        "gh.org.list.id" => copilot_user.copilot_organizations.pluck(:id),
        "gh.business.list.id" => copilot_user.copilot_businesses.pluck(:id)
      })
      deliver_error!(403)
    end
    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)

    deliver_error!(404) unless authorizer.has_cfb_access? || authorizer.has_cfe_access?

    repo_nwo = params[:repo].to_s.strip
    repo_nwo = nil if repo_nwo.empty?

    if repo_nwo
      unless repo_nwo.match?(%r{\A[a-zA-Z0-9\-_.+]+/[a-zA-Z0-9\-_.+]+\z})
        deliver_error!(400, message: "Invalid repo parameter format. Expected owner/repo-name.")
      end
    end

    # Telemetry: per RFC github/copilot-ecosystem#934 §6, emit a request counter
    # so the migration progress dashboard can compare traffic to `/v1`. The
    # legacy endpoint has no resolved spec version, so tag with `none`.
    emit_mcp_registry_request_counter(endpoint: "legacy", spec_version: "none")

    # Gate the GitHub Enterprise MCP Registry filter behind a feature flag while
    # URL-only legacy clients (e.g., the CLI allowlist integration) migrate to the
    # versioned `/v1` endpoint. URL-only clients cannot authenticate against the
    # GitHub-native registry, so once they have moved off this endpoint the flag
    # can be turned on to drop GitHub Enterprise entries from the legacy response.
    # The flag is resolved through `Copilot::Mcp::FeatureFlags` so the name and
    # default live in one place and can be flipped at either the enterprise or
    # actor level. Default is off so existing clients keep seeing the URL during
    # migration.
    exclude_github_enterprise_registry = Copilot::Mcp::FeatureFlags
      .legacy_exclude_github_enterprise_registry?(copilot_user)
    registries = get_mcp_registries(
      copilot_user,
      repo_nwo: repo_nwo,
      exclude_github_enterprise_registry: exclude_github_enterprise_registry,
    )
    data = registries.map(&:to_h)

    deliver_raw({ mcp_registries: data })
  end

  # GET /copilot/mcp_registry/v1 is the versioned sibling of the legacy
  # /copilot/mcp_registry endpoint described in RFC
  # github/copilot-ecosystem#934. It uses a path-major envelope (`/v1`) plus a
  # Stripe-style `X-Spec-Version` request header for additive evolution and
  # drops `registry_access` / `owner.priority` from the wire shape, returning
  # the full 0..N applicable registries (no most-restrictive-wins collapse).
  # The selection logic is shared with the legacy endpoint via
  # `RegistryApiHelper#get_mcp_registries(for_v1: true)` so the two routes
  # cannot drift.
  get "/copilot/mcp_registry/v1", operation_id: :internal do
    @route_owner = "@github/copilot-ecosystem"

    control_access :copilot_mcp_registry,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)

    unless copilot_user.mcp_enabled?
      GitHub.logger.info("Request made by user without access to MCP", {
        "code.function" => "get_mcp_registry_v1",
        "gh.org.list.id" => copilot_user.copilot_organizations.pluck(:id),
        "gh.business.list.id" => copilot_user.copilot_businesses.pluck(:id)
      })
      deliver_error!(403)
    end
    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)

    deliver_error!(404) unless authorizer.has_cfb_access? || authorizer.has_cfe_access?

    repo_nwo = params[:repo].to_s.strip
    repo_nwo = nil if repo_nwo.empty?

    if repo_nwo
      unless repo_nwo.match?(%r{\A[a-zA-Z0-9\-_.+]+/[a-zA-Z0-9\-_.+]+\z})
        deliver_error!(400, message: "Invalid repo parameter format. Expected owner/repo-name.")
      end
    end

    # Resolve the requested spec version before dispatching. An unknown value
    # still returns the latest shape, but we annotate the response so the
    # client can detect a stale pin without breaking on body-shape diffs.
    resolved = Copilot::Mcp::V1::SpecVersion.resolve(request.env["HTTP_X_SPEC_VERSION"])

    # Telemetry: request counter dimensioned by endpoint, resolved spec version
    # and client UA family (RFC github/copilot-ecosystem#934 §6). The resolved
    # spec version is tagged (not the raw header) so the dashboard answers
    # "what shape did we serve?". Client drift on the raw pin is captured
    # separately by the `unknown_spec_version` counter below.
    emit_mcp_registry_request_counter(endpoint: "v1", spec_version: resolved.resolved)

    if resolved.unknown?
      GitHub.logger.info("Unknown MCP registry v1 spec version requested", {
        "code.function" => "get_mcp_registry_v1",
        "gh.copilot.mcp_registry.requested_spec_version" => resolved.requested,
        "gh.copilot.mcp_registry.resolved_spec_version" => resolved.resolved,
      })
      # Telemetry: dimension client drift by the requested pin so we can detect
      # which value(s) clients are sending. The raw value is sanitized to a
      # bounded alphabet before tagging so a pathological header cannot blow
      # up tag cardinality on Datadog.
      GitHub.dogstats.increment(
        "copilot.mcp_registry.unknown_spec_version",
        tags: [
          "endpoint:v1",
          "requested:#{sanitize_mcp_registry_spec_version_tag(resolved.requested)}",
          "client_user_agent:#{mcp_registry_user_agent_family}",
        ],
      )
      headers["Deprecation"] = "true"
      # Escape the requested value for inclusion in the RFC 7234 quoted warning
      # text. Backslashes and double quotes are the only characters that need
      # escaping inside a quoted-string; other characters are passed through.
      escaped_requested = resolved.requested.to_s.gsub(/[\\"]/) { |c| "\\#{c}" }
      headers["Warning"] = %Q{299 - "Unknown X-Spec-Version \\"#{escaped_requested}\\"; serving latest (#{resolved.resolved}). Update the pin to a known version."}
    end

    # Telemetry: emit the allowlist-availability signal as its own counter so
    # the dashboard can compute a `true / (true + false)` ratio across tenants
    # without joining on tag combinations. We sample the same source the v1
    # `_meta` envelope uses so the metric cannot drift from the wire signal.
    GitHub.dogstats.increment(
      "copilot.mcp_registry.allowlist_available",
      tags: [
        "endpoint:v1",
        "allowlist_available:#{Copilot::Mcp::V1::Meta.allowlist_available?(copilot_user)}",
        "client_user_agent:#{mcp_registry_user_agent_family}",
      ],
    )

    body = Copilot::Mcp::V1::Handler.call(
      spec_version: resolved.resolved,
      copilot_user: copilot_user,
      repo_nwo: repo_nwo,
    )

    # Cache headers per RFC §3. The body varies with `X-Spec-Version` (different
    # pins legitimately yield different shapes) and with `Accept` (we may add
    # representations later), in addition to the usual authenticated-vary set.
    # `must-revalidate` prevents a stale-while-revalidate intermediary from
    # serving an out-of-date allowlist while the registry is rotating.
    body_fingerprint = ::Digest::SHA256.hexdigest(GitHub::JSON.encode(body))
    etag_value = %Q{"#{body_fingerprint}"}

    headers["Cache-Control"] = "private, max-age=60, must-revalidate"
    headers["Vary"] = "X-Spec-Version, Accept, Authorization, Cookie, X-GitHub-OTP"
    headers["ETag"] = etag_value

    if_none_match = request.env["HTTP_IF_NONE_MATCH"].to_s.strip
    unless if_none_match.empty?
      matched =
        if if_none_match == "*"
          # Per RFC 7232 §3.2, "*" matches any current representation; we
          # always have one here, so the precondition fails and we 304.
          true
        else
          # Weak compare each validator per RFC 7232 §2.3.2: strip an
          # optional `W/` prefix from each token, then compare octet-by-octet
          # against the server-issued ETag (we only emit strong validators).
          if_none_match.split(/\s*,\s*/).any? do |token|
            stripped = token.start_with?("W/") ? token[2..-1].to_s : token
            stripped == etag_value
          end
        end
      halt 304 if matched
    end

    deliver_raw(body)
  end

  # Filter top repos by query, handling owner/repo format and user login prefix.
  # Mirrors the query normalization from RepositorySearch#smart_search without ES.
  sig { params(query: String, top_repos: T::Array[Repository], viewer: User).returns(T::Array[Repository]) }
  def filter_top_repos(query, top_repos, viewer)
    # Handle "owner/repo" format
    if query.include?("/")
      owner_part, repo_part = query.split("/", 2).map(&:strip)
      if owner_part.present? && repo_part.present?
        owner_down = owner_part.downcase
        repo_down = repo_part.downcase
        return top_repos.select do |r|
          r.owner_display_login.downcase.include?(owner_down) &&
            r.name.downcase.include?(repo_down)
        end
      end
      # "owner/" with no repo part — treat as plain owner query
      query = owner_part if owner_part.present?
    end

    # Strip user's own login prefix (e.g., "tclem/dotfiles" -> "dotfiles")
    user_login = viewer.display_login.downcase
    if query.downcase.start_with?("#{user_login}/")
      query = query.sub(/\A#{Regexp.escape(user_login)}\//i, "").strip
    end

    lower_query = query.downcase
    top_repos.select { |r| r.name_with_display_owner.downcase.include?(lower_query) }
  end

  sig { params(env: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, String]) }
  def copilot_headers(env)
    headers = ActionDispatch::Http::Headers.from_hash(env)
    editor_version = headers["Editor-Plugin-Version"].to_s
    editor_plugin_version = headers["Editor-Version"].to_s

    log_headers(env, editor_version, editor_plugin_version) if editor_version.blank? && editor_plugin_version.blank? && user_agent.present?

    {
      asn: headers["HTTP_X_AS"].to_s,
      editor_plugin_version: headers["Editor-Plugin-Version"].to_s,
      editor_version: headers["Editor-Version"].to_s,
      github_api_version: headers["X-GitHub-Api-Version"].to_s,
      ip_address: headers["api.remote_ip"].to_s,
      real_ip: platform_context[:real_ip],
      request_id: headers["HTTP_X_GITHUB_REQUEST_ID"].to_s,
      user_agent: user_agent.to_s,
    }
  end

  sig { params(env: T::Hash[T.untyped, T.untyped], editor_version: String, editor_plugin_version: String).void }
  def log_headers(env, editor_version, editor_plugin_version)
    GitHub.dogstats.increment("copilot.authorizer.editor_version_missing")
    keys = request.env.keys.map(&:to_s).select do |key|
      # check if key is all caps and has a dash
      key.match?(/\A[A-Z_\-]+\z/)
    end.sort

    GitHub.logger.info(
      "Editor version and plugin version are missing",
      "gh.copilot.request_keys" => keys,
      "gh.copilot.editor_version" => editor_version,
      "gh.copilot.editor_plugin_version" => editor_plugin_version,
      "gh.copilot.user_agent" => user_agent.to_s,
    )
  end

  # Emit the `copilot.mcp_registry.requests` counter for either MCP registry
  # endpoint. Per RFC github/copilot-ecosystem#934 §6 the migration progress
  # dashboard slices traffic by `endpoint` (legacy vs v1), `spec_version`
  # (resolved, where applicable; `none` for legacy), and `client_user_agent`
  # (a bounded family — see `mcp_registry_user_agent_family`).
  sig { params(endpoint: String, spec_version: String).void }
  def emit_mcp_registry_request_counter(endpoint:, spec_version:)
    GitHub.dogstats.increment(
      "copilot.mcp_registry.requests",
      tags: [
        "endpoint:#{endpoint}",
        "spec_version:#{spec_version}",
        "client_user_agent:#{mcp_registry_user_agent_family}",
      ],
    )
  end

  # Bounded mapping from the raw User-Agent string to a small set of Copilot
  # client families. Datadog tag cardinality is a finite resource, so the raw
  # UA is intentionally not tagged — full UAs are still available via the
  # standard request log if we need to drill in. The fallback `unknown` keeps
  # ratios honest by ensuring every request emits exactly one family.
  sig { returns(String) }
  def mcp_registry_user_agent_family
    raw = user_agent.to_s
    return "unknown" if raw.empty?

    lower = raw.downcase
    case lower
    when /github[ -]?cli/, /\bgh\//
      "github-cli"
    when /copilot[ -]?chat/
      "vscode-copilot-chat"
    when /vscode|visual studio code/
      "vscode"
    when /jetbrains|intellij|rider|pycharm|goland|webstorm|phpstorm|rubymine|clion|datagrip|appcode|androidstudio/
      "intellij-platform"
    when /visual ?studio|visualstudio/
      "visual-studio"
    when /xcode/
      "xcode"
    when /neovim|nvim/
      "neovim"
    when /\bvim\b/
      "vim"
    when /eclipse/
      "eclipse"
    when /emacs/
      "emacs"
    else
      "unknown"
    end
  end

  # Sanitize the requested `X-Spec-Version` value for use as a Datadog tag
  # value. Limits to a bounded alphabet (`[A-Za-z0-9._-]`) and length (32) so a
  # pathological header value cannot inflate tag cardinality or break the
  # statsd protocol. Empty / nil values collapse to `empty` so the counter
  # always carries a tag.
  sig { params(value: T.nilable(String)).returns(String) }
  def sanitize_mcp_registry_spec_version_tag(value)
    return "empty" if value.nil? || value.empty?

    cleaned = value.gsub(/[^A-Za-z0-9._-]/, "_")
    truncated = cleaned[0, 32].to_s
    truncated.empty? ? "empty" : truncated
  end

  sig do
    params(
      copilot_user: Copilot::User,
      all_policies: Copilot::Users::Policies::CopilotAllPolicies,
      cli_remote_control_value: String,
      cloud_session_storage_value: T.nilable(String),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def copilot_cli_policy_details_with_observability(copilot_user:, all_policies:, cli_remote_control_value:, cloud_session_storage_value:)
    GitHub.dogstats.distribution_time("copilot.user.policy_details.duration") do
      Copilot::Policies::CliPolicyDetails.call(
        copilot_user: copilot_user,
        all_policies: all_policies,
        cli_remote_control_value: cli_remote_control_value,
        cloud_session_storage_value: cloud_session_storage_value,
      )
    end
  rescue StandardError => error
    GitHub.dogstats.increment("copilot.user.policy_details.error", tags: ["exception_class:#{error.class.name}"])
    { error: "internal_error" }
  end

  # Whether the user should be treated as GitHub/Microsoft staff. True when the user is:
  #   * a GitHub employee (the github enterprise / @github/employees team) on dotcom, ignoring
  #     the "disable employee mode" footer override so the flag reflects real staff status, or
  #   * a member of the Microsoft enterprise managed users (EMU) enterprise on dotcom, or
  #   * on one of the Microsoft-operated Proxima stamps (msft.ghe.com / microsoft.ghe.com), or
  #   * on a Microsoft-internal staff Proxima stamp (stamp name starting with "staff-",
  #     e.g. staff-wus2-01).
  sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
  def staff?(copilot_user)
    user = copilot_user.user_object

    if GitHub.multi_tenant_enterprise?
      return true if GitHub.copilot_stamp&.start_with?(STAFF_PROXIMA_STAMP_PREFIX)

      return MICROSOFT_PROXIMA_STAMP_SLUGS.include?(GitHub::CurrentTenant.get&.slug)
    end

    return true if user.employee_ignoring_override?

    user.is_enterprise_managed? && user.enterprise_managed_business&.slug == MICROSOFT_EMU_ENTERPRISE_SLUG
  end
end
