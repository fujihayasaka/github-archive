# typed: true
# frozen_string_literal: true

class Stafftools::ProximaServiceRateLimitsController < StafftoolsController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::ProximaServiceRateLimitsController#create",
    "Stafftools::ProximaServiceRateLimitsController#destroy",
    "Stafftools::ProximaServiceRateLimitsController#update",
  ]

  before_action :dotcom_required # not available in enterprise
  before_action :require_feature_enabled

  before_action :require_service_identity, only: [:update, :destroy]
  before_action :validate_params, only: [:create, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot

  def index
    render "stafftools/proxima_service_rate_limits/index"
  end

  def create
    if ProximaServiceIdentity.find_by(tenant_shortcode: @tenant_shortcode, service_name: @service_name)
      flash[:error] = "Rate limit configuration for '#{@service_name}' service on the '#{@tenant_shortcode}' tenant already exists."
      return redirect_to stafftools_proxima_service_rate_limits_path
    end

    service_identity = ProximaServiceIdentity.create!(
      tenant_shortcode: @tenant_shortcode,
      service_name: @service_name,
      rate_limit: @rate_limit
    )

    flash[:notice] = "Successfully created rate limit configuration for '#{@service_name}' service on the '#{@tenant_shortcode}' tenant."

    redirect_to stafftools_proxima_service_rate_limits_path(service_name: params[:service_name])
  end

  def update
    @service_identity.tenant_shortcode = @tenant_shortcode
    @service_identity.service_name = @service_name
    @service_identity.rate_limit = @rate_limit
    if @service_identity.changed?
      if @service_identity.save
        flash[:notice] = "Successfully updated rate limit configuration for '#{@service_identity.service_name}' service on the '#{@service_identity.tenant_shortcode}' tenant."
      else
        flash[:error] = "An unexpected error occurred. Please try again."
      end
    else
      flash[:warn] = "Nothing changed in rate limit configuration for '#{@service_identity.service_name}' service on the '#{@service_identity.tenant_shortcode}' tenant."
    end
    redirect_to stafftools_proxima_service_rate_limits_path(service_name: @service_identity.service_name)
  end

  def destroy
    if @service_identity.destroy
      flash[:notice] = "Successfully deleted rate limit configuration for '#{@service_identity.service_name}' service on the '#{@service_identity.tenant_shortcode}' tenant."
    else
      flash[:error] = "An unexpected error occurred. Please try again."
    end

    redirect_to stafftools_proxima_service_rate_limits_path(service_name: @service_identity.service_name)
  end

  private

  def validate_params
    @tenant_shortcode = params[:tenant_shortcode]
    unless @tenant_shortcode.present?
      flash[:error] = "Tenant shortcode is required."
      return redirect_to stafftools_proxima_service_rate_limits_path
    end

    @service_name = params[:service_name]
    unless @service_name.present? && ProximaServiceIdentity::REGISTERED_SERVICES.include?(@service_name)
      flash[:error] = "Service '#{@service_name}' is not a registered service."
      return redirect_to stafftools_proxima_service_rate_limits_path
    end

    @rate_limit = Integer(params[:rate_limit], exception: false)
    if @rate_limit.blank?
      flash[:error] = "Rate limit is required."
      return redirect_to stafftools_proxima_service_rate_limits_path
    end

    if @rate_limit.present? && @rate_limit <= ProximaServiceIdentity.default_rate_limit(@service_name)
      flash[:error] = "Rate limit registration for the '#{@service_name}' service must be greater than #{ProximaServiceIdentity.default_rate_limit(@service_name)} (default)."
      redirect_to stafftools_proxima_service_rate_limits_path
    end
  end

  def require_service_identity
    unless params[:id].present?
      flash[:error] = "Service identity is required"
      return head :bad_request
    end

    @service_identity = ProximaServiceIdentity.find_by(id: params[:id])
    unless @service_identity
      flash[:error] = "Unable to find the target identity (#{params[:id]})"
      head :bad_request
    end
  end

  def require_feature_enabled
    render_404 unless GitHub.flipper[:proxima_service_rate_limits].enabled?
  end
end
