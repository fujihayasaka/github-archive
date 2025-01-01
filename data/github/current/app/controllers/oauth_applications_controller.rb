# typed: true
# frozen_string_literal: true

class OauthApplicationsController < ApplicationController
  include OrganizationsHelper
  include OauthApplicationsHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Lodge,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Lodge,
    only: [:advanced]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Lodge,
    only: [:beta_features]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Lodge,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Lodge,
    only: [:show, :oauth_authorizations]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:advanced, :beta_features, :show, :new, :oauth_authorizations], optional: true

  MAX_APPS_FLASH_ERROR_MESSAGE = "You can't create any more OAuth Apps. You've reached the limit for the number of applications owned by this account.".freeze

  before_action :login_required_or_org_admins_only
  before_action :ensure_if_organization_required
  before_action :sudo_filter, only: [:revoke_all_tokens, :transfer, :generate_client_secret, :remove_client_secret]
  before_action :set_cache_control_no_store, only: [:index, :show, :update]
  before_action :check_apps_creation_limit, only: [:new]
  before_action :find_application!, except: [:index, :new, :create]
  before_action :set_developer_settings_context_region
  before_action :check_valid_target, only: [:transfer]

  helper_method :beta_features_available?, :current_application, :async_oauth_authorizations_path, :total_authorizations

  javascript_bundle :settings
  stylesheet_bundle :settings

  def index
    case current_context.class.name.downcase
    when "organization"
      @applications = current_context.oauth_applications.limit(15).page(params[:page])
      @pending_transfers = current_context.inbound_application_transfers

      render "oauth_applications/organization", locals: { can_create_applications: !current_context.archived? }
    else
      render_404
    end
  end

  def new
    @application = populate(params, current_context.oauth_applications.build)
    render "oauth_applications/new"
  end

  def create
    @application = populate(params, current_context.oauth_applications.build)

    if @application.save
      flash[:notice] = "Application created successfully"
      redirect_to oauth_application_path(@application)
    else
      render "oauth_applications/new"
    end
  rescue ::DietEarthsmoke::DietEarthsmokeError
    flash[:notice] = "Application creation timed out, please try again."
    render "oauth_applications/new"
  end

  def show
    respond_to do |format|
      format.html do
        render "oauth_applications/show"
      end
    end
  end

  def update
    @application = populate(params, @application)

    if @application.save
      flash[:notice] = "Application updated successfully"
      redirect_to oauth_application_path(@application)
    else
      render "oauth_applications/show"
    end
  end

  def destroy
    unless @application.can_delete?
      if request.xhr?
        return head 422
      else
        flash[:error] = "The Application failed to be deleted because it has active marketplace subscriptions."
        return redirect_to oauth_application_path(@application)
      end
    end

    @application.async_destroy
    flash[:notice] = "Job queued to delete application. It may take a few minutes to complete."

    if request.xhr?
      head 200
    else
      redirect_to oauth_applications_path
    end
  end

  def transfer # rubocop:todo GitHub/UseRestfulActions
    xfer = OauthApplicationTransfer.start(application: @application, target: target, requester: current_user)
    if target.adminable_by?(current_user)
      redirect_to settings_application_transfer_path(target, xfer.id)
    else
      flash[:notice] = "Application transfer request sent to #{target.display_login}"
      redirect_to oauth_application_path(@application)
    end

  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = "Unable to request application transfer"
    redirect_to oauth_application_path(@application)
  end

  def revoke_all_tokens # rubocop:todo GitHub/UseRestfulActions
    @application.async_revoke_tokens(entry_point: :oauth_applications_controller_revoke_all_tokens)
    @application.instrument "revoke_all_tokens"

    flash[:notice] = "Job queued to revoke all user tokens"
    redirect_to oauth_application_path(@application)
  end

  def generate_client_secret # rubocop:todo GitHub/UseRestfulActions
    secret = @application.generate_client_secret(creator: current_user)
    flash[:new_client_secret] = { id: secret.id, secret: secret.secret }
    redirect_to oauth_application_path(@application)
  end

  def remove_client_secret # rubocop:todo GitHub/UseRestfulActions
    client_secret = @application.client_secrets.find_by_id(params[:secret_id])
    if client_secret.nil?
      redirect_to oauth_application_path(@application), notice: "Client secret already removed"
    elsif client_secret.destroy
      redirect_to oauth_application_path(@application), notice: "Client secret removed"
    else
      redirect_to oauth_application_path(@application), notice: "Client secret not removed"
    end
  end

  private def target_for_conditional_access
    # This controller uses the login_required_or_org_admins_only before every action,
    # preventing access from anonymous users despite CAP.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    this_organization || current_user
  end

  memoize def this_organization # rubocop:todo GitHub/UseRestfulActions
    return unless params[:organization_id]

    Organization.find_by(login: params[:organization_id])
  end

  def advanced # rubocop:todo GitHub/UseRestfulActions
    render "oauth_applications/advanced"
  end

  def beta_features # rubocop:todo GitHub/UseRestfulActions
    render "oauth_applications/beta_features"
  end

  def oauth_authorizations # rubocop:todo GitHub/UseRestfulActions
    render partial: "oauth_applications/oauth_authorizations"
  end

  private

  memoize def target
    User.find_by!(login: params[:transfer_to])
  end

  def beta_features_available?
    Apps::BetaFeatureComponent::BETA_FEATURES.any? do |_, hash|
      global_flag = hash[:global_flag]
      GitHub.flipper[global_flag].enabled?(current_application.user)
    end
  end

  def current_application # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @application if defined?(@application)
    @application = find_application
  end

  def populate(params, application)
    hash = params[:oauth_application] || {}
    application.name = hash[:name] if hash[:name]
    application.bgcolor = hash[:bgcolor] if hash[:bgcolor]
    application.url = hash[:url].strip if hash[:url]
    application.description = hash[:description] if hash[:description]
    application.callback_url = hash[:callback_url].strip if hash[:callback_url]
    application.pinned_api_version = hash[:pinned_api_version] if hash[:pinned_api_version].present?
    application.device_flow_enabled = hash[:device_flow_enabled] if hash[:device_flow_enabled].present?
    if hash[:callback_urls]
      application.set_application_callback_urls(
        hash[:callback_urls].map { |callback_url| callback_url.strip },
      )
    end

    if logo_id = hash.fetch(:logo_id, nil)
      application.logo = OauthApplicationLogo.find_by(id: logo_id, uploader_id: current_user.id)
    end

    application
  end

  def find_application
    current_context.oauth_applications.find_by(id: params[:id])
  end

  def find_application!
    return @application if defined?(@application)

    @application = find_application

    return render_404 unless @application

    @application
  end

  def check_apps_creation_limit
    if current_context.reached_applications_creation_limit?(application_type: OauthApplication)
      flash[:error] = MAX_APPS_FLASH_ERROR_MESSAGE

      if current_context.is_a? Organization
        redirect_to settings_org_applications_path(current_context)
      else
        redirect_to settings_user_developer_applications_path
      end
    end
  end

  def check_valid_target
    return unless current_context.feature_enabled?(:block_emu_transfers_to_non_emu_target)

    render_404 unless @application.valid_target?(target)
  end

  def set_developer_settings_context_region
    context_region_preset :developer_settings
  end

  def async_oauth_authorizations_path
    if this_organization
      settings_org_applications_oauth_authorizations_path(organization_id: this_organization.to_param, id: current_application.id)
    else
      settings_user_applications_oauth_authorizations_path(id: current_application.id)
    end
  end

  memoize def total_authorizations
    current_application.authorizations.count
  end

  def ensure_if_organization_required
    render_404 if current_context.is_a?(Organization) && current_context&.deleted?
  end
end
