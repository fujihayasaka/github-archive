# typed: true
# frozen_string_literal: true

module AgentSourcesControllerMethods
  extend ActiveSupport::Concern
  include GitHub::Memoizer
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :login_required
    before_action :sudo_filter
    before_action :set_developer_settings_context_region
    before_action :ensure_can_edit_integration!
  end

  def show
    return render_404 unless agent_mode_create_feature_enabled?

    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )

    render "integrations/settings/agent_setup", locals: { view: view }
  end

  def new
    return render_404 unless agent_mode_create_feature_enabled?

    current_integration.build_agent_source unless current_integration.agent_source

    view = create_view_model(
      Integrations::ShowView,
      integration: current_integration
    )

    render "integrations/settings/new_agent_setup", locals: { view: view }
  end

  def create
    return render_404 unless agent_mode_create_feature_enabled?

    if current_integration.agent_source
      return redirect_to gh_settings_app_agent_setup_path(current_integration),
        notice: "Agent features have already been added. You can update them here."
    end

    permissions_acknowledged = params[:permissions_acknowledged] == "1"

    unless permissions_acknowledged
      current_integration.validate
      Integration::AgentSourceCreator.validate_agent_source(
        integration: current_integration,
        agent_source_params: agent_source_action_params
      )
      view = create_view_model(Integrations::ShowView, integration: current_integration)
      render "integrations/settings/new_agent_setup", locals: { view: view, show_permissions_acknowledgment_error: true }
      return
    end

    result = Integration::AgentSourceCreator.add_agent_source(
      integration: current_integration,
      agent_source_params: agent_source_action_params
    )

    if result.ok?
      instrument_integration_update

      redirect_to gh_settings_app_agent_setup_path(current_integration),
        notice: "Agent features have been added to your GitHub App."
    else
      view = create_view_model(Integrations::ShowView, integration: current_integration)
      render "integrations/settings/new_agent_setup", locals: { view: view, show_permissions_acknowledgment_error: false }
    end
  end

  def update
    return render_404 unless agent_mode_create_feature_enabled?

    agent_source_attrs = agent_source_action_params

    saved = if current_integration.agent_source
      current_integration.agent_source.update(agent_source_attrs).tap do |success|
        unless success
          current_integration.agent_source.errors.each do |error|
            current_integration.errors.add(:"agent_source.#{error.attribute}", error.message)
          end
        end
      end
    else
      Integration::AgentSourceCreator.add_agent_source(
        integration: current_integration,
        agent_source_params: agent_source_attrs
      ).ok?
    end

    if saved
      instrument_integration_update
      redirect_to gh_settings_app_agent_setup_path(current_integration),
        notice: "Got it. Your GitHub App has been updated."
    else
      view = create_view_model(Integrations::ShowView, integration: current_integration)
      render "integrations/settings/agent_setup", locals: { view: view }
    end
  end

  def destroy
    return render_404 unless agent_mode_create_feature_enabled?

    if current_integration.agent_source&.destroy
      instrument_integration_update

      redirect_to gh_settings_app_agent_setup_path(current_integration),
        notice: "Got it. Your GitHub App has been updated."
    else
      flash.now[:error] = "Something went wrong removing Agent features. Please try again."
      show
    end
  end

  def tenant_verification_enforceable
    logged_in? ? :yes : :no
  end

  def emu_visibility_enforceable
    logged_in? ? :yes : :no
  end

  private

  # Private: Returns the correct target depending on if we're working
  # with org, user, or business integrations.
  #
  # Returns an Organization, User, or Business
  def current_context
    raise NotImplementedError
  end

  def current_integration
    current_context.integrations.not_marked_for_deletion.find_by!(slug: params[:id])
  end
  memoize :current_integration

  def ensure_can_edit_integration!
    render_404 unless Apps::ManagementHelper.can_edit?(app: current_integration, actor: current_user)
  end

  def set_developer_settings_context_region
    if current_context.nil? || !current_context.business?
      context_region_preset :developer_settings
    end
  end

  def agent_mode_create_feature_enabled?
    FeatureFlag.vexi.enabled?(:agentic_app_creation_form_updates, current_context, default: false)
  end

  def instrument_integration_update
    return unless current_integration.feature_flag_enabled?(:integration_update_hydro_event, default: true)

    current_integration.reload

    GlobalInstrumenter.instrument "integration.update", {
      integration: current_integration,
      actor: current_user,
      owner: current_context
    }
  end

  def agent_source_action_params
    params.require(:integration).permit(agent_source: %i(repository_id commit_oid))
      .fetch(:agent_source, {}).to_h
  end
end
