# typed: true
# frozen_string_literal: true

class Businesses::SecurityAnalysisController < Businesses::BusinessController
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
    :update,
    :update_resource_link,
    :user_namespace_ghas_toggle,
    :actions_runners_labels,
  ]

  # Access
  before_action :business_required
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
    :update,
    :update_resource_link,
    :user_namespace_ghas_toggle,
  ]

  before_action :parse_json_params, only: [
    :apply_configuration,
    :apply_confirmation_summary,
    :create,
    :update_ai_detection,
    :update,
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
    :update,
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
    only: [:index, :new, :edit, :repositories_count, :show, :actions_runners_labels]

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  def index
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: this_business)
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
      title: "GitHub Advanced Security",
      page_data: {
        selected_link: :business_security_analysis,
        sidebar: :settings
      },
      layout: "react_business",
    )
  end

  def show
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: this_business)
    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Advanced Security · Show configuration · #{this_business.name}",
      page_data: {
        selected_link: :business_security_analysis,
        sidebar: :settings
      },
      layout: "react_business",
    )
  end

  def new
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: this_business)
    render_react_app(
      payload: default_payload,
      title: "Advanced Security · New configuration · #{this_business.name}",
      page_data: {
        selected_link: :business_security_analysis,
        sidebar: :settings
      },
      layout: "react_business",
    )
  end

  def create
    klass = this_business.advanced_security_products_bundled? ? SecurityConfiguration : UnbundledSecurityConfiguration
    saved_config = klass.create_configuration(
      model_hash: security_configuration_params(this_business).merge({ "target" => this_business }),
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
      enforcement: params[:enforcement]&.to_sym,
      actor: current_user,
      options: params[:options]
    )

    if saved_config.errors.any?
      render json: { errors: saved_config.errors.to_hash }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def edit
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: this_business)
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
        sidebar: :settings
      },
      layout: "react_business",
    )
  end

  def update
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
    errors = []
    total_repo_count = 0
    bundled = this_business.advanced_security_products_bundled?
    licenses_needed, code_scanning_licenses_needed, secret_scanning_licenses_needed = 0, 0, 0
    code_scanning_licenses_missing, secret_scanning_licenses_missing = 0, 0

    if security_configuration.enables_paid_features?
      billable_entity = AdvancedSecurityLicense.billable_entity(this_business)
      billable_entity = T.must_because(billable_entity) { "Businesses passed into billable_entity always return themselves" }

      begin
        if bundled
          summary = billable_entity.advanced_security_license.summary
          licenses_needed = summary.additional_committers

          allowance_exceeded = billable_entity.advanced_security_license.allowance_exceeded?
          will_exceed_allowance = licenses_needed > billable_entity.advanced_security_license.remaining_seats
          errors.append("license_limit_exceeded") if allowance_exceeded || will_exceed_allowance
        else
          if security_configuration.code_security_sku_enabled(billable_entity:)
            code_security = billable_entity.code_security
            summary = code_security.summary
            code_scanning_licenses_needed = summary.additional_committers

            if code_security.purchased?
              errors.append("code_security_license_limit_exceeded") if code_security.allowance_exceeded?

              if !code_security.unlimited_seats? && (code_scanning_licenses_needed > code_security.remaining_seats)
                code_scanning_licenses_missing = [0, code_scanning_licenses_needed - code_security.remaining_seats].max
                errors.append("applying_will_exceed_code_security_license_limit")
              end
            end
          end

          if security_configuration.secret_protection_sku_enabled(billable_entity:)
            secret_protection = billable_entity.secret_protection
            summary = secret_protection.summary
            secret_scanning_licenses_needed = summary.additional_committers

            if secret_protection.purchased?
              errors.append("secret_protection_license_limit_exceeded") if secret_protection.allowance_exceeded?

              if !secret_protection.unlimited_seats? && (secret_scanning_licenses_needed > secret_protection.remaining_seats)
                secret_scanning_licenses_missing = [0, secret_scanning_licenses_needed - secret_protection.remaining_seats].max
                errors.append("applying_will_exceed_secret_protection_license_limit")
              end
            end
          end
        end
      rescue AdvancedSecurityLicense::TurboghasError => e
        Failbot.report(e)
        errors << "internal_ghas_error"
      end
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
      bundled:,
      licenses_needed:,
      total_repo_count:,
      uses_action_minutes: security_configuration.uses_action_minutes?,
      code_scanning_licenses_needed:,
      code_scanning_licenses_missing:,
      secret_scanning_licenses_needed:,
      secret_scanning_licenses_missing:,
      errors:,
    }
  end

  def repositories_count # rubocop:todo GitHub/UseRestfulActions
    render json: {
      repo_count: security_configuration_serializer.repositories_count(security_configuration)
    }
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

  def actions_runners_labels # rubocop:disable GitHub/UseRestfulActions
    render json: { labels: SecurityProductsEnablement::Actions::RunnerChecker.new(this_business).labels }
  end

  private

  def business_required
    render_404 unless this_business
  end

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

    return nil if generic_secrets.nil?
    return nil if generic_secrets.show_security_config_ux?
    return nil if !generic_secrets.feature_available?

    generic_secrets.enabled?
  end
end
