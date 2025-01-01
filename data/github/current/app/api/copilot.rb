# typed: true
# frozen_string_literal: true

class Api::Copilot < Api::App
  include FeatureFlagHelper
  include Scientist
  include BlackbirdIndexHelper
  include Copilot::ContentExclusion::ApiHelper

  get "/copilot_internal/v2/token", operation_id: :internal do
    @route_owner = "@github/copilot"

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
      if current_user.feature_enabled?(:copilot_business_secondary_auth_check) && copilot_user.has_pending_auth_checks?
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
      envelope = Copilot::Envelope.new(authorizer, headers)
      envelope.instrument_token_generation(headers)
      deliver_raw(envelope.envelope.sort.to_h)
    else
      # moving the envelope down here because we want to check the ip first up there
      envelope = Copilot::Envelope.new(authorizer, headers)
      envelope.instrument_token_failure(authorizer.reason, headers)
      halt deliver_raw(envelope.envelope.sort.to_h, status: 403)
    end
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
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
  post "/copilot_internal/notification", operation_id: :internal do
    @route_owner = "@github/copilot"

    # This is the only check we're doing - just making sure they
    # are coming from the IDE
    #
    # This is a different name in case we want to check this differently
    control_access :copilot_notification,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive(Hash)
    notification_id = data.fetch("notification_id", nil)

    deliver_error!(404) unless notification_id.present?

    copilot_user = Copilot::User.new(current_user)
    acknowledged = copilot_user.acknowledge_notification(notification_id, user_agent: user_agent.to_s)

    deliver_raw({ notification_id: notification_id, acknowledged: acknowledged })
  end

  post "/copilot_internal/repository_check", operation_id: :internal do
    @route_owner = "@github/copilot"
    control_access :copilot_repository_check,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_error!(404)
  end

  # This endpoint is to check a user's Copilot license/subscription status
  get "/copilot_internal/user", operation_id: :internal do
    @route_owner = "@github/copilot"
    deliver_error!(404) if GitHub.enterprise? || GitHub.multi_tenant_enterprise?

    control_access :copilot_user_status,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    copilot_user = Copilot::User.new(current_user)
    authorizer = copilot_user.copilot_authorizer_object_no_snippy

    organizations = authorizer.organizations
    GitHub::PrefillAssociations.prefill_associations(organizations.map(&:organization_object), [:profile])

    organization_list = organizations.map do |org|
      { login: org.display_login, name: org.profile_name }
    end

    deliver_raw({
      access_type_sku: authorizer.access_type_sku,
      assigned_date: copilot_user.assigned_date,
      chat_enabled: copilot_user.chat_enabled?,
      organization_login_list: authorizer.organization_login_list,
      organization_list:
    })
  end

  get "/copilot_internal/content_exclusion", operation_id: :internal do
    @route_owner = "@github/copilot"

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
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    copilot_error = Copilot::Errors::ContentExclusionError.from_error(e)
    Copilot::ErrorReporter.report!(copilot_error, copilot_user: copilot_user)
    deliver_error!(404)
  end

  get "/copilot_internal/check_indexing_status", operation_id: :internal do
    @route_owner = "@github/blackbird"

    nwo = params[:nwo] || ""
    repo = Repository.nwo(nwo)

    record_or_404(repo)

    control_access :get_repo,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    tenant = ::Search::Blackbird::Client.tenant(current_tenant)
    actor = ::Search::Blackbird::Client.api_actor(current_user, remote_ip, api_auth.token)
    response = get_indexing_status(current_user, actor, repo, tenant)
    response[:can_index] = can_index_embeddings_status(current_user, repo)
    deliver_raw(response)
  end

  get "/copilot_internal/workspace", operation_id: :internal do
    @route_owner = "@github/copilot"

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
      copilot_user = Copilot::User.new(current_user)
      response = {
        copilot_workspace_enabled: copilot_user.workspace_enabled?,
      }
      deliver_raw(response)
    else
      GitHub.dogstats.increment("copilot.workspace.failure")
      GitHub.logger.error("HMAC signature was invalid")
      deliver_error!(401, message: result)
    end
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
      ip_address: headers["api.remote_ip"].to_s,
      real_ip: platform_context[:real_ip],
      request_id: headers["HTTP_X_GITHUB_REQUEST_ID"].to_s,
      user_agent: user_agent.to_s,
    }
  end

  sig { params(env: T::Hash[T.untyped, T.untyped], editor_version: String, editor_plugin_version: String).void }
  def log_headers(env, editor_version, editor_plugin_version)
    return unless current_user.feature_enabled?(:copilot_log_missing_editor_version)

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
