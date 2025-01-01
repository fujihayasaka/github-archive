# typed: true
# frozen_string_literal: true

class Businesses::SecurityAnalysisController < Businesses::BusinessController
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::SecurityConfigurationsDependency

  allow_verified_fetch only: [
    :apply_configuration,
    :apply_confirmation_summary,
    :create,
    :destroy,
    :repositories_count,
    :update_ai_detection,
    :update_config,
    :update_resource_link,
    :user_namespace_ghas_toggle,
  ]

  # Access
  before_action :view_permission_required, only: [:index, :new]
  before_action :modify_permission_required, except: [:index]
  before_action :business_full_plan_required

  # Enterprise-level configs feature flag for new endpoints:
  before_action :security_configuration, only: [
    :create,
    :edit,
    :new,
    :repositories_count,
    :show,
    :update_ai_detection,
    :update_config,
    :update_resource_link,
    :user_namespace_ghas_toggle,
  ]

  before_action :parse_json_params, only: [
    :apply_configuration,
    :apply_confirmation_summary,
    :create,
    :update_ai_detection,
    :update_config,
    :update_resource_link,
    :user_namespace_ghas_toggle,
  ]

  before_action :security_configuration, only: [
    :apply_configuration,
    :apply_confirmation_summary,
    :destroy,
    :edit,
    :repositories_count,
    :show,
    :update_config,
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:index, :new, :edit, :repositories_count, :show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:ghas_settings]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:ghas_settings], optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  def index
    add_client_feature_flag([:enterprise_security_configurations_private_beta_label], entity: this_business)

    if SecurityProductsEnablement.enterprise_configs_enabled?(this_business)
      render_react_app(
        payload: default_payload.merge({
          githubRecommendedConfiguration: serialized_github_recommended_configuration,
          customEnterpriseSecurityConfigurations: serialized_enterprise_security_configurations,
          orgFailures: org_failures,
          additionalSettings: {
            resourceLink: resource_link,
            aiDetection: generic_secrets,
            advancedSecurityEnabledNewRepos: this_business.advanced_security_enabled_on_new_user_namespace_repos?,
            secretScanningEnabledNewRepos: SecretScanning::Features::Business::TokenScanning.new(this_business).secret_scanning_enabled_for_new_repos?,
            pushProtectionEnabledNewRepos: push_protection.enabled_for_new_repos?,
          },
        }),
        title: "Code security and analysis",
        page_data: {
          selected_link: :business_security_analysis,
        },
        layout: "react_business",
        ssr: true,
      )
    else
      render "businesses/settings/security_analysis", locals: {
        business: this_business,
        public_repo_count:,
        repo_count:,
      }
    end
  end

  def show
    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Show security configuration · #{this_business.name}",
      page_data: {
        selected_link: :business_security_analysis,
      },
      layout: "react_business",
      ssr: true,
    )
  end

  def new
    render_react_app(
      payload: default_payload,
      title: "Settings · New security configuration · #{this_business.name}",
      page_data: {
        selected_link: :business_security_analysis,
      },
      layout: "react_business",
      ssr: true,
    )
  end

  def create
    saved_config = SecurityConfiguration.create_configuration(
      security_configuration_params(this_business).merge({ "target" => this_business }),
      params[:default_for_new_public_repos],
      params[:default_for_new_private_repos],
      params[:enforcement]&.to_sym,
      params[:options]
    )

    if saved_config.errors.any?
      render json: { errors: saved_config.errors.to_hash }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # FIXME: This is the legacy `update` method, once we retire the original page we should replace this with `update_config`
  def update
    error_message = UpdateSecuritySettings.perform(this_business, params, actor: current_user).try(:fetch, :error, nil)
    return redirect_to(:back, flash: { error: error_message }) if error_message.present?

    flash[:notice] = "Security settings updated for #{this_business.name}'s repositories. It may take a few minutes to process."

    redirect_to settings_security_analysis_enterprise_path(this_business, show_update_tip: params[:show_update_tip], show_alert_tip: params[:show_alert_tip])
  end

  def edit
    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Edit security configuration · #{this_business.name}",
      page_data: {
        selected_link: :business_security_analysis,
      },
      layout: "react_business",
      ssr: true,
    )
  end

  # FIXME: Rename this to `update` once we retire the original page.
  def update_config # rubocop:todo GitHub/UseRestfulActions
    security_configuration.update_configuration(
      security_configuration_params(this_business).merge({ "target" => this_business }),
      T.must(current_user),
      type: :enterprise,
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
      enforcement: params[:enforcement]&.to_sym,
      options: params[:options],
    )

    if security_configuration.errors.any?
      render json: { errors: security_configuration.errors.to_hash }, status: :unprocessable_entity
    else
      render json: {}, status: :ok
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    if security_configuration.is_github_recommended_configuration?
      render_404
    else
      security_configuration.delete_configuration(current_user)
      head :no_content
    end
  end

  def apply_configuration # rubocop:todo GitHub/UseRestfulActions
    return unless SecurityProductsEnablement.enterprise_configs_enabled?(this_business)

    options = {
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
    }

    if params[:source] == "enterprise_config_table"
      security_configuration.create_or_update_defaults(
        this_business,
        ActiveModel::Type::Boolean.new.cast(params[:default_for_new_public_repos]),
        ActiveModel::Type::Boolean.new.cast(params[:default_for_new_private_repos])
      )
    end

    SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
      security_configuration_id: security_configuration.id,
      enterprise_id: this_business.id,
      actor_id: T.must(T.must(current_user).id),
      action: :apply,
      override_existing_config: params[:override_existing_config] == true,
      user_session_id: user_session.id,
      options:
    )

    head :created
  end

  def apply_confirmation_summary # rubocop:todo GitHub/UseRestfulActions
    return unless SecurityProductsEnablement.enterprise_configs_enabled?(this_business)

    errors = []
    total_repo_count = 0

    if params[:enable_ghas]
      begin
        billable_entity = AdvancedSecurityLicense.billable_entity(this_business)
        summary = AdvancedSecurityLicense.summary(entity: T.must(billable_entity))
        licenses_needed = summary.additional_committers
      rescue AdvancedSecurityLicense::TurboghasError => e
        Failbot.report(e)
        errors << "internal_ghas_error"
      end
    else
      licenses_needed = 0
    end

    if params[:override_existing_config]
      this_business.organizations.each do |org|
        total_repo_count += org.repositories.count
      end
    else
      this_business.organizations.each do |org|
        repos_with_configs_in_org = RepositorySecurityConfiguration.where(organization_id: org.id).applied_or_attaching.count
        total_repo_count += org.repositories.count - repos_with_configs_in_org
      end
    end

    render json: {
      licenses_needed:,
      total_repo_count:,
      uses_action_minutes: security_configuration.uses_action_minutes?,
    }
  end

  def repositories_count # rubocop:todo GitHub/UseRestfulActions
    render json: {
      repo_count: security_configuration_serializer.repositories_count(security_configuration)
    }
  end

  def ghas_settings # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Settings::SecurityAnalysisGhasSettingsComponent.new(
          owner: this_business,
          public_repo_count:,
          repo_count:,
          cursor: nil,
          custom_patterns_query: nil
        ), layout: false
      end
    end
  end

  def update_resource_link # rubocop:todo GitHub/UseRestfulActions
    if params[:input].blank?
      # If the input is blank, the feature is disabled:
      job_params = { push_protection_custom_message_status: "disabled" }
    else
      # Else we will update the resource link if validation passes:
      job_params = { enable_and_set_push_protection_custom_message: params[:input] }
    end

    error_message = UpdateSecuritySettings.perform(this_business, job_params, actor: current_user).try(:fetch, :error, nil)

    if error_message.present?
      render json: { success: false, error_message: }, status: :unprocessable_entity
    else
      render json: { success: true }, status: :accepted
    end
  end

  def update_ai_detection # rubocop:todo GitHub/UseRestfulActions
    filtered_params = params.select { |k, _| "secret_scanning_generic_secrets" == k }
    error_message = UpdateSecuritySettings.perform(this_business, filtered_params, actor: current_user).try(:fetch, :error, nil)

    if error_message.present?
      render json: { success: false, error_message: }, status: :unprocessable_entity
    else
      render json: { success: true }, status: :accepted
    end
  end

  def user_namespace_ghas_toggle # rubocop:todo GitHub/UseRestfulActions
    if params[:toggle].in? %w(enable_all disable_all)
      job_params = { advanced_security_user_namespace: params[:toggle] }
    elsif params[:toggle].in? %w(enabled disabled)
      case params[:setting]
      when "advanced_security_enabled_new_repos"
        job_params = { advanced_security_enabled_new_user_namespace_repos: params[:toggle] }
      when "secret_scanning_new_repos"
        job_params = { secret_scanning_new_repos: params[:toggle] }
      when "secret_scanning_push_protection_new_repos"
        job_params = { secret_scanning_push_protection_new_repos: params[:toggle] }
      else
        render json: { success: false, error_message: "Invalid setting" }, status: :unprocessable_entity
        return
      end
    else
      render json: { success: false, error_message: "Invalid input" }, status: :unprocessable_entity
      return
    end

    error_message = UpdateSecuritySettings.perform(this_business, job_params, actor: current_user).try(:fetch, :error, nil)

    if error_message.present?
      render json: { success: false, error_message: }, status: :unprocessable_entity
    else
      render json: { success: true }, status: :accepted
    end
  end

  private

  def view_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_view_code_security_settings?
  end

  def modify_permission_required
    business_authz = SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user)
    render_404 unless business_authz.can_modify_code_security_settings?
  end

  def public_repo_count
    # equivalent to Repository.where(...).public_scope.count
    repo_counts_by_public&.dig(true) || 0
  end

  def repo_count
    # equivalent to Repository.where(...).count
    repo_counts_by_public&.values&.sum || 0
  end

  memoize def repo_counts_by_public
    this_business.organizations.pluck(:id)
      .in_groups_of(1000, false)
      .map do |org_id_batch|
        Repository
          .where(owner_id: org_id_batch)
          .group(:public)
          .count
      end
      .reduce do |acc, hash|
        # merge hashes by key and sum the values
        acc.merge(hash) { |_key, *values| values.sum }
      end
  end

  def ensure_security_configurations_enabled
    render_404 unless SecurityProductsEnablement.enterprise_configs_enabled?(this_business)
  end

  def push_protection
    SecretScanning::Features::Business::PushProtection.new(this_business)
  end

  # Helper for populating the resourceLink in the payload. If push protection is disabled we return nil, else we return the value.
  # This is necessary because push protection can be disabled while the value is still set, and we want to hide the value in the UI.
  def resource_link
    push_protection.custom_message_enabled? ? this_business.get_push_protection_custom_message : nil
  end

  # Helper for populating the AI Detection toggle in the payload. If the feature is not available we return nil, else we return the value.
  def generic_secrets
    generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(this_business)

    return nil if !generic_secrets.feature_available?

    generic_secrets.enabled?
  end
end
