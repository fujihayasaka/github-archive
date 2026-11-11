# typed: strict
# frozen_string_literal: true

class Businesses::AuditLogMicrosoftPurviewSinkController < Businesses::BusinessController
  ENTRA_CLIENT_ID = T.let("719015ea-85dc-4992-b6f4-8220d8fe9145", String)
  ADMIN_CONSENT_URL = T.let("https://login.microsoftonline.com/organizations/adminconsent", String)
  CSRF_COOKIE_NAME = T.let(:purview_csrf_token, Symbol)
  SINK_NAME = T.let("Microsoft Purview", String)
  RELAY_FLOW = T.let("audit_log_microsoft_purview", String)

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let(
    ["Businesses::AuditLogMicrosoftPurviewSinkController#initiate"].freeze,
    T::Array[String],
  )

  before_action :business_owner_required, only: [:authorize, :initiate, :show]
  before_action :audit_log_streaming_enabled?, only: [:authorize, :initiate, :show]
  before_action :audit_log_streaming_multiple_endpoints_enabled?, only: [:authorize, :initiate, :show]
  before_action :audit_log_microsoft_purview_enabled?, only: [:authorize, :initiate, :show]
  before_action :add_entra_form_action_csp, only: [:authorize]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:authorize, :initiate, :entra_callback, :show]

  around_action :select_write_database, only: [:entra_callback]

  # GET /enterprises/:slug/settings/audit-log/streams/microsoft-purview/authorize
  #
  # Landing page — explains the Entra admin consent flow and presents a button
  # to proceed. No credentials to collect; the tenant ID is returned by Entra.
  sig { void }
  def authorize # rubocop:todo GitHub/UseRestfulActions
    render "businesses/audit_log_microsoft_purview_sink/authorize", locals: { business: current_business }
  end

  # POST /enterprises/:slug/settings/audit-log/streams/microsoft-purview/authorize
  #
  # Generates a state token, persists it, and redirects the user to the Entra admin consent page.
  sig { void }
  def initiate # rubocop:todo GitHub/UseRestfulActions
    state = SecureRandom.urlsafe_base64(40)

    relay_state = RelayState.initiate(
      request_id: state,
      nonce: state,
      data: { business_id: current_business.id, flow: RELAY_FLOW },
    )

    cookies.encrypted[CSRF_COOKIE_NAME] = {
      value: relay_state.digest,
      expires: RelayState::DEFAULT_EXPIRY.from_now,
      secure: request.ssl?,
      httponly: true,
    }

    consent_url = "#{ADMIN_CONSENT_URL}?#{{
      client_id: ENTRA_CLIENT_ID,
      redirect_uri: "#{GitHub.url}#{enterprises_microsoft_purview_entra_callback_path}",
      state: state,
    }.to_query}"
    GitHub.logger.info(
      "Initiating Microsoft Purview Entra authorization",
      "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
      "gh.business.id" => current_business.id,
    )
    redirect_to consent_url, allow_other_host: true
  end

  # GET /enterprises/microsoft-purview/entra-callback
  #
  # Entra redirects back here with `tenant` and `state`; we look up
  # the state, run a preflight check, save the Purview sink configuration,
  # and redirect to streams list
  sig { void }
  def entra_callback # rubocop:todo GitHub/UseRestfulActions
    nonce = params[:state]
    tenant_id = params[:tenant]

    digest = cookies.encrypted[CSRF_COOKIE_NAME]
    cookies.delete(CSRF_COOKIE_NAME)

    # Check for an explicit error response from Entra (e.g. admin denied consent).
    # Entra includes `error` and `error_description` in the redirect when authorization is refused.
    # This should be done before any other checks, since an error response may not include the expected `state` or `tenant` params.
    if params[:error].present?
      GitHub.logger.warn(
        "Purview Entra callback returned error from Entra",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "entra.error" => params[:error],
        "entra.error_description" => params[:error_description],
      )
      flash[:error] = "Microsoft Entra authorization was denied or failed. Please try again."
      return redirect_to settings_enterprises_path
    end

    if nonce.blank? || tenant_id.blank?
      GitHub.logger.warn(
        "Purview Entra callback missing required params",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
      )
      flash[:error] = "Missing required parameters from Entra authorization response. Please try again."
      return redirect_to settings_enterprises_path
    end

    if digest.blank?
      GitHub.logger.warn(
        "Purview Entra callback missing CSRF digest cookie",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
      )
      flash[:error] = "Invalid or expired authorization state. Please try again."
      return redirect_to settings_enterprises_path
    end

    relay_state = RelayState.consume(
      request_id: nonce,
      nonce: nonce,
      digest: digest,
    )

    unless relay_state&.ok?
      GitHub.logger.warn(
        "Purview Entra callback rejected invalid relay state",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
      )
      flash[:error] = "Invalid or expired authorization state. Please try again."
      return redirect_to settings_enterprises_path
    end

    unless relay_state.data["flow"] == RELAY_FLOW
      GitHub.logger.warn(
        "Purview Entra callback rejected mismatched relay flow",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => relay_state.data["business_id"],
      )
      flash[:error] = "Invalid or expired authorization state. Please try again."
      return redirect_to settings_enterprises_path
    end

    business = Business.find_by(id: relay_state.data["business_id"])
    unless business
      GitHub.logger.warn(
        "Purview Entra callback rejected unknown business",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => relay_state.data["business_id"],
      )
      flash[:error] = "Authorization state does not match the current enterprise. Please try again."
      return redirect_to settings_enterprises_path
    end

    return render_404 unless callback_authorized_for_business?(business)

    existing_purview_stream = business.audit_log_stream_configurations
      .includes(:sink)
      .where(sink_type: "AuditLogMicrosoftPurviewSinkConfiguration")
      .limit(AuditLogStreamConfiguration::MAX_AUDIT_LOG_STREAMS_ALLOWED)
      .find { |s| s.sink&.tenant_id == tenant_id }

    if existing_purview_stream
      flash[:error] = "A #{SINK_NAME} audit log stream is already configured for this Entra tenant."
      return redirect_to show_settings_audit_log_streams_enterprise_path(business)
    end

    sink = AuditLogMicrosoftPurviewSinkConfiguration.new(tenant_id: tenant_id)
    stream = business.audit_log_stream_configurations.build(sink: sink)

    # The relay state is consumed at this point — the user cannot retry this callback.
    # Always redirect to the streams list so they can restart the auth flow if needed.
    unless stream.check_sink_succeeded?(business, sink)
      GitHub.logger.warn(
        "Purview Entra callback preflight check failed",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => business.id,
      )
      flash[:error] = "Must have a successful endpoint check to save an audit log stream."

      return redirect_to show_settings_audit_log_streams_enterprise_path(business)
    end

    begin
      saved = stream.save
    rescue ActiveRecord::RecordNotUnique
      GitHub.logger.warn(
        "Purview Entra callback rejected duplicate stream",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => business.id,
      )
      flash[:error] = "Unable to create a duplicate audit log stream to #{SINK_NAME}."
      return redirect_to show_settings_audit_log_streams_enterprise_path(business)
    end

    if saved
      GitHub.logger.info(
        "Purview Entra callback configured stream successfully",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => business.id,
      )
      flash[:notice] = "Microsoft Purview audit log stream successfully configured."
    elsif stream.idx_taken?
      # idx uniqueness conflict — no flash, falls through to redirect below
    else
      GitHub.logger.warn(
        "Purview Entra callback failed to save stream",
        "code.namespace" => "Businesses::AuditLogMicrosoftPurviewSinkController",
        "gh.business.id" => business.id,
      )
      flash[:error] = "Unable to save #{SINK_NAME} configuration: #{stream.errors.full_messages.to_sentence}."
    end

    redirect_to show_settings_audit_log_streams_enterprise_path(business)
  end

  # GET /enterprises/:slug/settings/audit-log/streams/microsoft-purview/:id
  #
  # Read-only view of a configured Purview stream. Shows the saved tenant ID.
  # There are no customer-supplied credentials to update — users must delete and
  # recreate the stream to change their tenant or re-authorize.
  sig { void }
  def show
    id = params.extract_value(:id)
    stream = current_business.audit_log_stream_configurations.find_by(id: id)
    return render_404 if stream.nil?
    return render_404 unless stream.sink.is_a?(AuditLogMicrosoftPurviewSinkConfiguration)

    render "businesses/audit_log_microsoft_purview_sink/show", locals: { business: current_business, stream: stream }
  end

  private

  sig { void }
  def audit_log_microsoft_purview_enabled?
    return if microsoft_purview_feature_enabled?(current_business)
    render_404
  end

  sig { void }
  def audit_log_streaming_enabled?
    return if GitHub.driftwood_streaming_enabled?
    render_404
  end

  sig { void }
  def audit_log_streaming_multiple_endpoints_enabled?
    return if current_business.audit_log_multiple_streaming_endpoint_enabled?
    render_404
  end

  sig { params(business: Business).returns(T::Boolean) }
  def callback_authorized_for_business?(business)
    return false unless business.owner?(current_user)
    return false unless GitHub.driftwood_streaming_enabled?
    return false unless business.audit_log_multiple_streaming_endpoint_enabled?
    return false if GitHub.enterprise?
    microsoft_purview_feature_enabled?(business)
  end

  # Chrome enforces `form-action` against redirect targets from POST form
  # submissions. The initiate action redirects to login.microsoftonline.com,
  # so we must add it to the CSP on the page that renders the authorize form.
  sig { void }
  def add_entra_form_action_csp
    SecureHeaders.append_content_security_policy_directives(request, { form_action: %w[https://login.microsoftonline.com] })
  end

  sig { params(business: Business).returns(T::Boolean) }
  def has_azure_idp?(business)
    business.enterprise_managed_user_enabled? &&
      business.external_provider&.find_provider_type == :azure_ad
  end

  sig { params(business: Business).returns(T::Boolean) }
  def microsoft_purview_feature_enabled?(business)
    return false if GitHub.enterprise?
    return false unless has_azure_idp?(business)
    return false unless FeatureFlag.vexi.enabled?(:audit_log_streaming_microsoft_purview, business, default: false)
    return false unless FeatureFlag.vexi.enabled?(:copilot_api_enable_usage_record_telemetry, business, default: false)
    FeatureFlag.vexi.enabled?(:audit_log_streaming_add_copilot_events, business, default: false)
  end
end
