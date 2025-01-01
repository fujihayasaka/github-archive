# typed: true
# frozen_string_literal: true

class Api::Copilot < Api::App
  include FeatureFlagHelper
  include Scientist
  include BlackbirdIndexHelper
  include Copilot::ContentExclusion::ApiHelper
  include Copilot::McpRegistry::ApiHelper

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

    deliver_error!(403) if GitHub.multi_tenant_enterprise? && authorizer.has_cfi_access?

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
      halt deliver_raw(envelope.envelope.sort.to_h, status: 403)
    end
  rescue StandardError => e # rubocop:todo Lint/RescueException
    copilot_error = Copilot::Errors::TokenFailureError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
    Copilot::Instrumenter.instrument_token_failed(Copilot::User.new(current_user), "server_error", copilot_headers(env))

    error_envelope = {
      message: "Resource not accessible by integration",
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

    # This is the only check we're doing - just making sure they
    # are coming from the IDE
    #
    # This is a different name in case we want to check this differently

    control_access :copilot_notification,
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

      case restricted_telemetry
      when "enabled"
        copilot_user.enable_telemetry!
      when "disabled"
        copilot_user.disable_telemetry!
      else
        GitHub.logger.info "Unknown restricted_telemetry value: #{restricted_telemetry}"
        copilot_user.enable_telemetry!
        restricted_telemetry = "enabled"
      end

      limited_user = copilot_user.limited_user

      response = {
        subscribed: true,
        public_code_suggestions: public_code_suggestions,
        restricted_telemetry: restricted_telemetry,
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
      { login: org.display_login, name: org.profile_name }
    end

    plan = copilot_user.copilot_plan
    plan = "individual_pro" if copilot_user.has_pro_plus_access?

    response = {
      access_type_sku: authorizer.access_type_sku,
      analytics_tracking_id: current_user.analytics_tracking_id,
      assigned_date: copilot_user.assigned_date,
      can_signup_for_limited: copilot_user.can_signup_for_limited?,
      chat_enabled: copilot_user.chat_enabled?,
      copilot_plan: plan,
      organization_login_list: authorizer.organization_login_list,
      organization_list:
    }

    if authorizer.access_type_sku == "free_limited_copilot"
      limited_user = Copilot::LimitedUser.for_subscribed_user(current_user)
      if limited_user.present?
        response["limited_user_quotas"] = limited_user.quotas_remaining
        # we want to show the day of the month that they subscribed
        response["limited_user_subscribed_day"] = limited_user.subscribed_at.day
        response["limited_user_reset_date"] = limited_user.reset_date
        response["monthly_quotas"] = Copilot::Quotas.monthly_quotas
      end
    end

    if copilot_user.consumptive_user?
      response["quota_reset_date"] = copilot_user.quota_reset_date
      response["quota_snapshots"] = copilot_user.quota_snapshots
      if FeatureFlag.vexi.enabled?(:copilot_quota_reset_date_utc, current_user, default: false)
        response["quota_reset_date_utc"] = copilot_user.quota_reset_date_utc
      end
    end

    Copilot::Instrumenter.instrument_internal_user_called(
      copilot_user,
      authorizer.access_type,
      headers,
    ) if authorizer.access_allowed?

    deliver_raw(response)
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
  rescue StandardError => e # rubocop:todo Lint/RescueException
    copilot_error = Copilot::Errors::ContentExclusionError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
    deliver_error!(404)
  end

  get "/repositories/:repository_id/copilot_internal/coding_guidelines", operation_id: :internal do
    @route_owner = "@github/copilot"

    control_access :copilot_coding_guidelines,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)

    if repository = find_repo!
      ensure_repo_is_accessible
    end
    deliver_error!(404) unless repository
    deliver_error!(403) unless repository.pullable_by?(current_user)

    unless copilot_user.copilot_coding_guidelines_enabled?(repository)
      GitHub.logger.info("Unexpected request for coding guidelines", {
        "code.function" => "get_coding_guidelines",
        "gh.repository.nwo" => repository.name_with_display_owner
      })
      deliver_error!(404)
    end

    authorizer = Copilot::Authorizer.new(copilot_user, GitHub.context)
    deliver_error!(404) unless authorizer.has_cfb_access?

    guidelines = Copilot::CodingGuideline.where(repository: repository, enabled: true)
        .limit(Copilot::CodingGuideline::MAX_PER_REPO)
        .map do |guideline|
          {
            name: guideline.name,
            description: guideline.description,
            filePatterns: guideline.paths.map { |path| path.path }
          }
        end
    deliver_raw guidelines
  rescue StandardError => e # rubocop:todo Lint/RescueException
    copilot_error = Copilot::Errors::CodingGuidelinesError.from_error(e)
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

  patch "/copilot_internal/chat_attachments/:attachment_id", operation_id: :internal do
    @route_owner = "@github/copilot-api"

    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error 404 unless current_user.feature_flag_enabled?(:copilot_chat_attachments, default: false)

    copilot_user = Copilot::Public::User.new(current_user)
    deliver_error 404 unless copilot_user.has_copilot_access?

    attachment = Copilot::ChatAttachment.uploaded_by(current_user).where(
      id: params[:attachment_id],
    ).first

    deliver_error 404 if attachment.nil?

    attachment = T.must(attachment)
    data = receive(Hash)

    if data["state"] == "uploaded"
      saved = attachment.track_uploaded

      if saved
        deliver_raw({
          url: attachment.permalink
        }, status: 201)
      else
        deliver_error 422, errors: attachment.errors
      end
    else
      deliver_error 422, message: "Only uploaded chat attachments states can be changed."
    end
  end

  get "/copilot/mcp_registry", operation_id: :internal do
    @route_owner = "@github/copilot"

    control_access :copilot_mcp_registry,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)

    unless FeatureFlag.vexi.enabled?(:copilot_mcp_registry_api, current_user, default: false)
      deliver_error!(404)
    end

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

    if FeatureFlag.vexi.enabled?(:copilot_mcp_registry_api_data, current_user, default: false)
      registries = get_mcp_registries(copilot_user)
      data = registries
    else
      data = MOCK_MCP_REGISTRY
    end

    deliver_raw({ mcp_registries: data })
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
end
