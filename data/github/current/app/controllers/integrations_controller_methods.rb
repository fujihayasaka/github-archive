# typed: true
# frozen_string_literal: true

module IntegrationsControllerMethods
  extend ActiveSupport::Concern
  include IntegrationManagerHelper
  include GranularPermissionsHelper
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { ApplicationController }

  RESOURCE_SUBJECT_TYPES = (Repository::Resources.subject_types + Organization::Resources.subject_types + User::Resources.subject_types + Business::Resources.subject_types)
  MAX_APPS_FLASH_ERROR_MESSAGE = "You can't create any more GitHub Apps. You've reached the limit for the number of applications owned by this account.".freeze

  included do
    include GitHub::RateLimitedRequest
    T.bind(self, T.class_of(ApplicationController))

    rate_limit_requests \
      only: [:receive_manifest],
      if: :anonymous_request?,
      max: 5,
      ttl: 1.minute,
      log_key: "receive-manifest-abuse",
      key: :rate_limit_key_by_ip

    before_action :login_required, except: [:receive_manifest]
    before_action :sudo_filter, except: [:index, :receive_manifest]
    before_action :check_apps_creation_limit, only: [:new]
    before_action :filter_unused_hook_attributes, only: [:create, :update]
    before_action :set_developer_settings_context_region

    before_action :check_valid_target, only: [:transfer]
    before_action :check_integration_transferable, only: [:transfer]

    # To prevent accidental foot-guns we prevent internal Apps from accessing
    # certain actions.
    #
    # See the `Apps::Privileged` property
    # `:allowed_integrations_controller_actions` for the complete list of
    # actions that internal Apps are allowed to access.
    before_action :apply_restrictions_for_current_integration

    stylesheet_bundle :settings

    helper_method :current_context

    depends_on_clusters ApplicationRecord::Mysql1,
                        ApplicationRecord::IamAbilities,
                        ApplicationRecord::Ballast,
                        ApplicationRecord::Collab,
                        ApplicationRecord::Configurations,
    only: [:transfer_suggestions]
  end

  def index
    @integrations = current_context.integrations.not_marked_for_deletion.not_for_github_connect.
      order("integrations.name asc").paginate(page: current_page, per_page: 15)

    pending_transfers = current_context.inbound_integration_transfers.includes(:integration, :requester)

    view = create_view_model(
      Integrations::IndexView,
      integrations: @integrations,
      pending_transfers: pending_transfers,
      owner: current_context
    )
    render "integrations/settings/index", locals: { view: view }
  end

  def show
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )
    render "integrations/settings/show", locals: { view: view }
  end

  def permissions
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )
    render "integrations/settings/integration_permissions", locals: { view: view }
  end

  def installations
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration,
      page: params[:page] || 1
    )
    render "integrations/settings/installations", locals: { view: view }
  end

  def advanced
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )
    render "integrations/settings/advanced", locals: { view: view }
  end

  def beta_features
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )
    render "integrations/settings/beta_features", locals: { view: view }
  end

  def beta_toggle
    flag = params["beta_feature"]
    value = params["beta_feature_toggle"]

    if (attribute = Integrations::ShowView.model_owned_opt_in_attribute(flag))
      value = Integrations::ShowView.enable_or_disable_to_boolean(value)

      begin
        current_integration.update!(attribute => value)
      rescue ActiveRecord::RecordInvalid => e
        Failbot.report(e)
        flash[:error] = "Something went wrong toggling that feature, please try again."
      end
    else
      Integrations::ShowView.toggle_feature(
        flag,
        value,
        integration: current_integration,
      )
      flash_message = Integrations::ShowView.toggle_feature_flash_message(flag, value, integration: current_integration)

      flash[:notice] = flash_message
    end

    redirect_to gh_settings_app_beta_features_path(current_integration)
  end

  def new
    insecure_hook_secret = params.delete(:webhook_secret)

    if insecure_hook_secret
      flash[:warn] = "Setting WebHook secret from URL params is not supported"
    end

    integration = current_context.integrations.build(build_integration_params)

    view = create_view_model(
      Integrations::FormView,
      integration: integration
    )
    render "integrations/settings/new", locals: { view: view }
  end

  def receive_manifest
    manifest = IntegrationManifest.new(data: params[:manifest], owner: current_context)
    owner_login = params[:organization_id] || "current_user"

    if manifest.valid?
      kv_data = {
        manifest: manifest[:data],
        owner: owner_login,
      }

      kv_data[:state] = params[:state] if params[:state].present?

      manifest_token = manifest.generate_kv_key
      Apps::KV.store.set(
        manifest_token,
        kv_data.to_json,
        expires: 5.minutes.from_now
      )

      cookies[:app_manifest_token] = {
        value: manifest_token,
        expires: 5.minutes.from_now,
        secure: request.ssl?,
        httponly: true
      }

      redirect_to new_from_manifest_path
    else
      view = create_view_model(
        Integrations::NewFromManifestView,
        manifest: manifest,
        owner: owner_login,
      )
      render "integrations/settings/invalid_manifest", locals: { view: view }
    end
  end

  def create
    return T.cast(self, Settings::IntegrationsController).create_manifest if create_integration_manifest_on_create?

    integration = current_context.integrations.build(create_integration_params)

    begin
      if integration.save
        flash[:integration_just_created] = true

        GlobalInstrumenter.instrument "integration.create", {
          integration: integration,
          actor: current_user,
          owner: current_context,
          from_manifest: false,
        }

        redirect_to gh_settings_app_path(integration)
      else
        render_with_errors(integration)
      end
    rescue ActiveRecord::RecordNotUnique
      render_with_errors(integration)
    end
  end

  def update
    if current_integration.update(
        IntegrationsControllerMethods.handle_deprecated_integrations_public_field(
          update_integration_params,
          app: current_integration
        )
    )
      if request.xhr?
        head :ok
      else
        redirect_to gh_settings_app_path(current_integration),
          notice: "Got it. Your GitHub App has been updated."
      end
    else
      if request.xhr?
        render json: current_integration.errors, status: :unprocessable_entity
      else
        view = create_view_model(
          Integrations::ShowView,
          integration: current_integration
        )
        render "integrations/settings/show", locals: { view: view }
      end
    end
  end

  def update_permissions
    result = Integration::PermissionsEditor.perform(
      integration: current_integration,
      permissions_and_events: update_integration_permissions_params,
    )

    if result.success?
      redirect_to gh_settings_app_path(current_integration),
        notice: "Got it. Your GitHub App has been updated."
    else
      flash.now[:error] = result.error
      view = create_view_model(
        Integrations::ShowView,
        integration: result.integration
      )
      render "integrations/settings/integration_permissions", locals: { view: view }
    end
  end

  def preview_note
    return render_404 unless params[:field]

    record = case params[:field]
    when "note"
      IntegrationVersion.new(note: params[:text])
    when "description"
      Integration.new(description: params[:text])
    end

    render html: T.must(record).body_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def generate_key
    key = current_integration.generate_key(creator: current_user)

    if key.valid?
      filename = [
        current_integration.slug,
        Date.today.iso8601,
        "private-key",
        "pem",
      ].map(&:parameterize).join(".")

      send_data key.private_key.to_pem,
        filename: filename,
        type: "application/x-pem-file",
        disposition: "attachment"
    else
      flash[:error] = "Could not generate a new key: #{key.errors.full_messages.to_sentence}"
      redirect_to gh_settings_app_path(current_integration)
    end
  end

  def remove_key
    public_key = current_integration.public_keys.find_by_id(params[:key_id])
    return render_404 if public_key.nil?

    if public_key.destroy
      if request.xhr?
        head :ok
      else
        redirect_to gh_settings_app_path(current_integration),
          notice: "Master key removed"
      end
    else
      if request.xhr?
        render status: :unprocessable_entity, json: { message: public_key.errors.full_messages.to_sentence }
      else
        redirect_to gh_settings_app_path(current_integration),
          notice: "Master key not removed"
      end
    end
  end

  def keys
    return redirect_to gh_settings_app_path(current_integration) unless request.xhr?

    respond_to do |format|
      format.html do
        render partial: "integrations/settings/keys", locals: {
          view: create_view_model(Integrations::ShowView, integration: current_integration)
        }
      end
    end
  end

  def make_public
    if current_integration.make_public
      redirect_to gh_settings_app_path(current_integration),
        notice: "The GitHub App is now public. Anyone is free to install it."
    else
      redirect_to gh_settings_app_path(current_integration),
        alert: "There was a problem trying to make this GitHub App public."
    end
  end

  def make_private
    if current_integration.can_make_private?

      if current_integration.make_private
        redirect_to gh_settings_app_path(current_integration),
          notice: "The GitHub App is now private. It can only be installed on this account."
      else
        redirect_to gh_settings_app_path(current_integration),
          alert: "There was a problem trying to make this GitHub App private."
      end

    else
      redirect_to gh_settings_app_path(current_integration),
        alert: "This GitHub App cannot be made private because it is already installed on other accounts."
    end
  end

  def destroy
    unless delete_verification_provided?
      return redirect_to gh_settings_app_path(current_integration),
        alert: "The GitHub App was not deleted. Please provide the correct verification phrase."
    end

    # Destroy the Bot in the background for performance reasons.
    current_integration.destroy_bot_asynchronously = true

    if current_integration.can_delete? && current_integration.destroy
      redirect_to gh_settings_apps_path(current_context),
        notice: "Job queued to delete GitHub App. It may take a few minutes to complete."
    else
      flash[:error] = "The GitHub App failed to be deleted. Please try again"

      view = create_view_model(
        Integrations::ShowView,
        integration: current_integration
      )
      render "integrations/settings/show", locals: { view: view }
    end
  end

  # When transferring organization-owned Integrations this action is protected
  # by authz checks in before filters defined in
  # `app/controllers/orgs/integrations_controller.rb`.
  def transfer
    result = Integration::Transfers::Service.start!(
      integration: current_integration,
      target: target,
      requester: current_user
    )

    if result.success?
      return redirect_to_transfer_path(current_integration.transfer)
    end

    flash[:error] = result.message

    # When transfer fails
    if Apps::ManagementHelper.can_edit?(app: current_integration, actor: current_user)
      redirect_to gh_settings_app_path(current_integration)
    else
      redirect_to gh_settings_apps_path(current_context)
    end
  end

  def transfer_suggestions # rubocop:todo GitHub/UseRestfulActions
    view = create_suggestions_view

    visible_suggestions = cap_filter.authorized_resources(view.suggestions)
    visible_suggestions = visible_suggestions.filter.reject do |suggestion|
      suggestion == current_integration.owner
    end
    render Apps::Transfers::TargetAutocompleteComponent.new(
      suggestions: visible_suggestions,
    )
  end

  def revoke_all_tokens
    current_integration.async_revoke_tokens(entry_point: :integrations_controller_revoke_all_tokens)
    current_integration.instrument "revoke_all_tokens"

    redirect_to gh_settings_apps_path(current_context),
      notice: "Job queued to revoke all user tokens"
  end

  def generate_client_secret
    secret = current_integration.generate_client_secret(creator: current_user)
    flash[:new_client_secret] = { id: secret.id, secret: secret.secret }
    redirect_to gh_settings_app_path(current_integration)
  end

  def remove_client_secret
    client_secret = current_integration.client_secrets.find_by_id(params[:secret_id])
    if client_secret.nil?
      redirect_to gh_settings_app_path(current_integration), notice: "Client secret already removed"
    elsif client_secret.destroy
      redirect_to gh_settings_app_path(current_integration), notice: "Client secret removed"
    else
      redirect_to gh_settings_app_path(current_integration), notice: "Client secret not removed"
    end
  end

  def copilot
    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )

    render "integrations/settings/copilot", locals: { view: view }
  end

  def update_copilot
    if !Copilot::ExtensionsAgreementSignature.signed_by?(current_context)
      flash[:error] = "You must accept the Marketplace Developer Agreement."
      return redirect_to gh_settings_app_integration_agent_path(current_integration)
    end

    begin
      if current_integration.integration_agent.nil?
        current_integration.create_integration_agent!(update_integration_agent_params)
      else
        current_integration.integration_agent.update!(update_integration_agent_params)
      end


      redirect_to gh_settings_app_integration_agent_path(current_integration),
        notice: "Your GitHub App's Agent configuration has been updated."
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = e.record.errors.full_messages.join(", ")
      if current_integration.integration_agent&.errors&.any?
        current_integration.integration_agent.errors.clear
      end
      copilot
    end
  end

  def sign_agreement
    if params[:accept] == "true"
      begin
        Copilot::ExtensionsAgreementSignature.sign!(signatory: current_user, context: current_integration.owner)
      rescue ActiveRecord::RecordInvalid => e
        Failbot.report(e)
        flash[:error] = "Failed to sign the agreement. Please try again"
      end
    else
      flash[:error] = "You must accept the Marketplace Developer Agreement."
    end

    redirect_to gh_settings_app_integration_agent_path(current_integration)
  end

  # TODO: Remove this once we've updated the UI to handle the new
  # `integrations.visibility` enum attribute and deprecated the `public` field
  # from the integration manifest.
  #
  # Accepts and returns input_params as either a Hash (from the integration_manifest or as
  # a ActionController::Parameters (from the various IntegrationsController
  # classes that include this module).
  #
  # When supplied, the `app` argument is used to determine the default
  # visibility: "internal" for enterprise-owned apps and "private" for user and
  # org owned apps. Used when updating an app to prevent overwriting the
  # existing visibility.
  #
  # https://github.com/github/ecosystem-apps/issues/6122
  def self.handle_deprecated_integrations_public_field(input_params, app: nil)
    # If both `public` and `visibility` params are supplied, we _always_ prefer
    # `visibility`.
    params = input_params.is_a?(Hash) ? ActionController::Parameters.new(input_params) : input_params

    safe_default_visibility = app&.enterprise_owned? ? :internal_visibility : :private_visibility

    if !params.key?(:public) && !params.key?(:visibility) # No visibility supplied via either attribute, default to private (or internal) for safety.
      params[:visibility] = safe_default_visibility unless app.present? # Only relevant on create action, when we need to preserve the default behavior of public: false
    elsif params.key?(:public)
      public_param = params.extract!(:public)["public"] # Always remove the `public` field from the params because it doesn't work with `visibility`.

      if !params.key?(:visibility)
        case public_param
        when "true", true
          params[:visibility] = :public_visibility
        when "false", false
          params[:visibility] = :private_visibility
        else # Safe explicit default.
          params[:visibility] = safe_default_visibility
        end
      end
    end

    if input_params.is_a?(Hash)
      params.permit!.to_hash # Must blanket "permit" whatever is in the params in order to convert back to a Hash.
    else
      params
    end
  end

  private

  def target
    @target ||= Integration::Transfers::Query.find_target_by_params(transfer_to: params[:transfer_to])
  end

  def create_integration_manifest_on_create?
    return false unless action_name == "create"
    params[:integration_manifest].present?
  end

  # Private: Returns the correct target depending on if we're working
  # with org or user integrations.
  #
  # Returns an Organization or a User
  def current_context
    raise NotImplementedError
  end

  def current_integration
    return @current_integration if defined?(@current_integration)
    @current_integration = \
      current_context.integrations.not_marked_for_deletion.find_by!(slug: params[:id])
  end

  def permitted_new_integration_attributes
    %i(
      name
      description
      url
      callback_url
      device_flow_enabled
      request_oauth_on_install
      setup_url
      setup_on_update
      public
      visibility
      single_file_name
      single_file_paths
      user_token_expiration_enabled
      pinned_api_version
    )
  end

  def permitted_integration_hook_attributes
    %i(url secret insecure_ssl active _destroy)
  end

  def build_integration_params
    params[:integration] = {}

    params[:integration][:default_permissions] = {}
    RESOURCE_SUBJECT_TYPES.each do |permitted_subject_type|
      action = params.delete(permitted_subject_type)
      next if action_blank?(action)

      params[:integration][:default_permissions][permitted_subject_type] = action.to_sym
    end

    events = Array(params.delete(:events))
    params[:integration][:default_events]    = events.select { |event| Integration::Events::SUPPORTED_EVENTS.include?(event) }
    params[:integration][:integrator_events] = events.select { |event| Integration::Events::INTEGRATOR_EVENTS.include?(event) }

    params[:integration][:hook_attributes]                = {}
    params[:integration][:hook_attributes][:url]          = params.delete(:webhook_url)
    params[:integration][:hook_attributes][:insecure_ssl] = params.delete(:webhook_insecure_ssl)
    params[:integration][:hook_attributes][:active]       = params.delete(:webhook_active)

    if params[:content_reference_domains]
      params[:integration][:content_reference] = params.delete(:content_reference_domains)
    end

    if params[:domain]
      params[:integration][:content_reference] ||= []
      params[:integration][:content_reference] << params.delete(:domain)
    end

    if params.key?(:callback_url) || params.key?(:callback_urls)
      callback_urls = if params.key?(:callback_url)
        # Delete in case someone tries to set both
        params.delete(:callback_urls)

        [params.delete(:callback_url)]
      elsif params.key?(:callback_urls)
        # Delete in case someone tries to set both
        params.delete(:callback_url)

        Array(params.delete(:callback_urls))
      end

      if T.must(callback_urls).any?
        iterator = 0

        params[:integration][:application_callback_urls_attributes] = T.must(callback_urls).each_with_object({}) do |url, hash|
          hash[iterator.to_s] = { "url" => url, "_destroy" => "false" }
          iterator += 1
        end
      end
    end

    permitted_new_integration_attributes.each do |attribute|
      next unless params.key?(attribute)
      params[:integration][attribute] = params.delete(attribute)
    end

    create_integration_params
  end

  def create_integration_params
    filtered_params = params.require(:integration).permit(
      *permitted_new_integration_attributes,
      default_permissions: permitted_default_permissions,
      integrator_events: [],
      default_events: [],
      single_file_paths: [],
      content_reference: [],
      hook_attributes: permitted_integration_hook_attributes,
      application_callback_urls_attributes: %i(url _destroy),
    ).with_defaults(
      integrator_events: [],
    )

    sanitize_create_integration_params(filtered_params)
  end

  def sanitize_create_integration_params(params)
    if params.key?(:application_callback_urls_attributes)
      urls_in_use = []

      params[:application_callback_urls_attributes].select! do |_, attrs|
        url = attrs["url"].to_s

        next false if urls_in_use.include?(url)
        urls_in_use << url

        true
      end
    end

    IntegrationsControllerMethods.handle_deprecated_integrations_public_field(params)
  end

  def update_integration_params
    params.require(:integration).permit(
      :name,
      :description,
      :url,
      :callback_url,
      :device_flow_enabled,
      :request_oauth_on_install,
      :setup_url,
      :setup_on_update,
      :bgcolor,
      :pinned_api_version,
      hook_attributes: permitted_integration_hook_attributes,
      application_callback_urls_attributes: %i(id url _destroy),
    )
  end

  def update_integration_permissions_params
    params.require(:integration).permit(
      :note,
      :single_file_name,
      single_file_paths: [],
      content_reference: [],
      integrator_events: [],
      default_events: [],
      default_permissions: permitted_default_permissions,
    ).with_defaults(
      integrator_events: [],
    )
  end

  def permitted_default_permissions
    default_permissions = params[:integration][:default_permissions] || HashWithIndifferentAccess.new

    default_permissions.reject! do |permission, action|
      RESOURCE_SUBJECT_TYPES.include?(permission) ? action_blank?(action) : false
    end

    default_permissions.empty? ? {} : default_permissions.keys
  end

  def build_hook_params
    create_integration_params[:hook_attributes].reject { |k, _| k == "_destroy" }
  end

  def delete_verification_provided?
    verification_pattern = %r{\A#{ Regexp.quote current_integration.name }\z}i

    params[:verify].to_s =~ verification_pattern
  end

  def apply_restrictions_for_current_integration
    return unless params[:id] # no need to apply restrictions if there is no current_integration

    allowed_actions = Apps::Privileged.property(
      current_user.site_admin? ? :allowed_integrations_controller_actions_for_site_admins : :allowed_integrations_controller_actions,
      app: current_integration
    ) || []

    return if allowed_actions.include?(:all_controller_actions)
    render_404 unless allowed_actions.include?(action_name)
  end

  def check_apps_creation_limit
    if current_context.reached_applications_creation_limit?(application_type: Integration)
      flash[:error] = MAX_APPS_FLASH_ERROR_MESSAGE
      redirect_to gh_settings_apps_path(current_context)
    end
  end

  def check_integration_transferable
    unless Integration::Transfers::Service.can_transfer?(integration: current_integration, target: target, stafftools_initiated: false)
      flash[:error] = "This GitHub App cannot be transferred."

      redirect_to gh_settings_app_path(current_integration)
    end
  end

  def check_valid_target
    render_404 unless current_integration.valid_target?(target)
  end

  # In order to show the Hook fields on the page when
  # there isn't a hook we have to build an new hook.
  #
  # This means that hook attributes will always be passed
  # in and therefore even if we don't want to create a hook
  # it tries to.
  #
  # This filters out the hook_attributes from the params
  # if it's just a default set of params.
  def filter_unused_hook_attributes
    default_hook_attributes = ActionController::Parameters.new({
      "url"          => "",
      "secret"       => "",
      "insecure_ssl" => "0",
      "active"       => "0",
    })

    if params.dig("integration", "hook_attributes") == default_hook_attributes
      params["integration"].delete("hook_attributes")
    end
  end

  def anonymous_request?
    !logged_in?
  end

  def render_with_errors(integration)
    if integration.errors.has_key?(:permission)
      flash.now[:error] = integration.errors.full_messages_for(:permission).join("\n")
    elsif integration.errors.has_key?(:default_events)
      flash.now[:error] = integration.errors.full_messages_for(:default_events).join("\n")
    end

    integration.build_hook(build_hook_params) unless integration.hook

    view = create_view_model(
      Integrations::FormView,
      integration: integration
    )
    render "integrations/settings/new", locals: { view: view }
  end

  def set_developer_settings_context_region
    if current_context.nil? || !current_context.business?
      context_region_preset :developer_settings
    end
  end

  def update_integration_agent_params
    params.require(:integration_agent).permit(
      { skill_data: [:name, :description, :url, :parameters, :return_type] },
      :url,
      :description,
      :client_authorization_url,
      :app_type,
      :token_exchange_enabled,
      :token_exchange_url,
      :third_party_token_header_key,
      :third_party_token_header_value,
    )
  end

  def redirect_to_transfer_path(xfer)
    if Apps::ManagementHelper.can_update_all_apps?(on: target, actor: current_user)
      redirect_to gh_settings_app_transfer_path(target, xfer.id)
    else
      flash[:notice] = "GitHub App transfer request sent to #{target.display_login}"
      redirect_to gh_settings_app_path(current_integration)
    end
  end

  def create_suggestions_view
    emu_biz = current_integration.owner_enterprise_managed_business

    create_view_model(AutocompleteView,
      query: params[:q],
      with_orgs: true,
      with_businesses: suggest_businesses?,
      scope_businesses_to_ids: transferable_businesses_for_app_owner,
      exclude_suspended: true,
      business: emu_biz
    )
  end

  def suggest_businesses?
    app_owner = current_integration.owner
    return false if app_owner.business?

    return false if transferable_businesses_for_app_owner.blank?

    user_belongs_to_emu_biz = if app_owner.organization?
      app_owner.enterprise_managed_user_enabled?
    else
      app_owner.is_enterprise_managed?
    end

    return false if current_integration.public_visibility? && !user_belongs_to_emu_biz

    true
  end

  memoize def transferable_businesses_for_app_owner
    app_owner = current_integration.owner
    return nil if app_owner.business?

    if app_owner.organization?
      [app_owner.business&.id]
    else
      app_owner.is_enterprise_managed? ? [app_owner.enterprise_managed_business.id] : app_owner.businesses.pluck(:id)
    end.compact
  end
end
