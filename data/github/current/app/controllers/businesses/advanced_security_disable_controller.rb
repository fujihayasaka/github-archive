# typed: true
# frozen_string_literal: true

# Controller for handling bulk disable of Advanced Security from the licensing page.
# This provides a one-click way for GHAS-enabled customers (metered or volume) to:
# 1. Set all enterprise policies to block GHAS enablement
# 2. Disable GHAS on all private repositories
class Businesses::AdvancedSecurityDisableController < Businesses::BusinessController
  include VerifiedFetchDependency

  allow_verified_fetch only: [:destroy]

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :feature_flag_required
  before_action :ghas_enabled_required
  before_action :not_self_serve_volume_required

  def destroy
    # Set all four enterprise policies to "not allowed"
    this_business.disallow_members_to_enable_advanced_security(actor: current_user)
    this_business.disallow_repo_admins_to_modify_advanced_security_enablement(actor: current_user)
    this_business.disallow_repo_admins_to_modify_secret_scanning_settings(actor: current_user)
    this_business.disallow_repo_admins_to_modify_code_security_enablement(actor: current_user)

    # Enqueue jobs to disable GHAS on all private repos across all orgs.
    # Only run the relevant jobs based on whether the enterprise uses bundled or unbundled SKUs:
    #   - Bundled (GHAS_VOLUME/GHAS_METERED): advanced_security_disable_all
    #   - Unbundled (split SKUs): secret_protection_disable_all + code_security_disable_all
    org_job_args = { owner: this_business, actor_id: current_user.id, entity_type: :organization }
    if this_business.advanced_security_products_bundled_for_entity?
      SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**org_job_args, update_type: :advanced_security_disable_all)
    else
      SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**org_job_args, update_type: :secret_protection_disable_all)
      SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**org_job_args, update_type: :code_security_disable_all)
    end

    # Also disable on EMU user-owned repos if this is an EMU enterprise
    if this_business.enterprise_managed_user_enabled?
      user_job_args = { owner: this_business, actor_id: current_user.id, entity_type: :user }
      if this_business.advanced_security_products_bundled_for_entity?
        SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**user_job_args, update_type: :advanced_security_disable_all)
      else
        SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**user_job_args, update_type: :secret_protection_disable_all)
        SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(**user_job_args, update_type: :code_security_disable_all)
      end
    end

    # Emit audit log event
    this_business.instrument(
      "advanced_security_disabled_and_blocked",
      actor: current_user,
      policies_updated: [
        "advanced_security.access",
        "advanced_security.allow_repo_admin_enablement",
        "secret_scanning.allow_repo_admin_settings",
        "code_security.allow_repo_admin_enablement"
      ],
      repo_disable_job_enqueued: true
    )

    # Set flash message for the redirect (works for both HTML and JSON paths since frontend redirects after JSON response)
    flash_message = "Advanced Security has been disabled and is not available for enablement in this enterprise."
    if this_business.advanced_security_metered_for_entity?
      flash_message += " Your billing will continue through the end of the current billing cycle."
    end
    flash[:notice] = flash_message

    respond_to do |format|
      format.html do
        redirect_to enterprise_licensing_path(this_business)
      end
      format.json do
        render json: { success: flash_message }
      end
    end
  end

  private

  def feature_flag_required
    unless FeatureFlag.vexi.enabled?(:disable_ghas_from_licensing_page, this_business, default: false)
      render_404
    end
  end

  def ghas_enabled_required
    unless this_business.advanced_security_purchased?
      respond_to do |format|
        format.html do
          flash[:error] = "This action is only available for customers with Advanced Security enabled."
          redirect_to enterprise_licensing_path(this_business)
        end
        format.json do
          render json: { error: "This action is only available for customers with Advanced Security enabled." }, status: :unprocessable_entity
        end
      end
    end
  end

  def not_self_serve_volume_required
    if this_business.has_self_serve_advanced_security? && !this_business.advanced_security_metered_for_entity?
      respond_to do |format|
        format.html do
          flash[:error] = "Self-serve volume customers should use Cancel subscription instead."
          redirect_to enterprise_licensing_path(this_business)
        end
        format.json do
          render json: { error: "Self-serve volume customers should use Cancel subscription instead." }, status: :unprocessable_entity
        end
      end
    end
  end
end
