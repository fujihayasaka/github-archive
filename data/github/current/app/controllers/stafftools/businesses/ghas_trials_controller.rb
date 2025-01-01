# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::GhasTrialsController < Stafftools::Businesses::BusinessBaseController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "#{self}#create",
    "#{self}#update",
    "#{self}#destroy"
  ].freeze, T::Array[String])

  before_action :dotcom_required
  before_action :validate_sku_param

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Notify,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::SecurityProductsEnablement,
    only: [:create, :update, :destroy]

  def create
    trial = make_trial(billable_entity: this_business, sku: sku_param)

    # Check if trial can be enabled
    errors = trial.enablement_errors(actor: User.ghost, api_access: false, stafftools_access: true)
    unless errors.empty?
      flash[:error] = errors.join(", ")
      return redirect_to stafftools_advanced_security_path(this_business.slug)
    end

    number_of_days = params[:number_of_days_for_trial]&.to_i
    sfdc_poc_url = params[:sfdc_poc_url]
    reset_private_repos_on_expiration = params[:reset_private_repos_on_expiration] == "true"

    if sfdc_poc_url.nil?
      flash[:error] = "sfdc_poc_url is required"
      return redirect_to stafftools_advanced_security_path(this_business.slug)
    end

    begin
      trial.enable(
        actor: current_user,
        days: number_of_days,
        stafftools_access: true,
        sfdc_poc_url: sfdc_poc_url,
        reset_private_repos_on_expiration: reset_private_repos_on_expiration
      )
      flash[:notice] = "#{sku_param.title} trial enabled successfully for #{number_of_days} days"
    rescue EnterpriseCloudOnboard::SKUTrial::EnablementError => err
      flash[:error] = err.message
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      flash[:error] = err.message
    end

    redirect_to stafftools_advanced_security_path(this_business.slug)
  end

  def update
    trial = make_trial(billable_entity: this_business, sku: sku_param)

    unless trial.enabled?
      flash[:error] = "No #{sku_param.title} trial"
      return redirect_to stafftools_advanced_security_path(this_business.slug)
    end

    number_of_days = params[:number_of_days_for_trial]&.to_i
    reset_private_repos_on_expiration = params[:reset_private_repos_on_expiration]

    if number_of_days.nil? || reset_private_repos_on_expiration.nil?
      flash[:error] = "Number of days for trial and reset on expiration are required"
      return redirect_to stafftools_advanced_security_path(this_business.slug)
    end

    begin
      trial.set_number_of_days(actor: User.ghost, days: number_of_days)
      trial.set_reset_on_expiration(actor: User.ghost, reset_on_expiration: reset_private_repos_on_expiration == "true")

      flash[:notice] = "#{sku_param.title} trial updated successfully"
    rescue EnterpriseCloudOnboard::SKUTrial::InvalidNumberOfDays => err
      flash[:error] = err.message
    rescue EnterpriseCloudOnboard::SKUTrial::WouldExpireError => err
      flash[:error] = err.message
    end

    redirect_to stafftools_advanced_security_path(this_business.slug)
  end

  def destroy
    trial = make_trial(billable_entity: this_business, sku: sku_param)

    if trial.reset_on_expiration?
      if trial.billable_entity.feature_flag_enabled_or_raise?(:reset_ghas_on_trial_expiration) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        sku_name = if sku_param == GitHub::Turboghas::SKU::SecretSecurity
          EnterpriseCloudOnboard::SecretProtectionTrial::SKU_NAME
        else
          EnterpriseCloudOnboard::CodeSecurityTrial::SKU_NAME
        end
        StopTrialJob.perform_later(billable_entity: this_business, sku_name: sku_name)
        flash[:notice] = "#{sku_param.title} trial will be stopped"
        return redirect_to stafftools_advanced_security_path(this_business.slug)
      end
    end

    trial.disable(actor: current_user)
    flash[:notice] = "#{sku_param.title} trial disabled successfully"
    redirect_to stafftools_advanced_security_path(this_business.slug)
  end

  private

  def sku_param
    GitHub::Turboghas::SKU.from_param(params[:sku])
  end
  memoize :sku_param

  def validate_sku_param
    make_trial(billable_entity: this_business, sku: sku_param)
  rescue ArgumentError
    render status: :not_found, json: { error: "Invalid SKU parameter" }
    false
  end

  def make_trial(billable_entity:, sku:)
    case sku
    when GitHub::Turboghas::SKU::SecretSecurity
      EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity)
    when GitHub::Turboghas::SKU::CodeSecurity
      EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity)
    else
      raise ArgumentError, "Unsupported SKU: #{sku}"
    end
  end
end
