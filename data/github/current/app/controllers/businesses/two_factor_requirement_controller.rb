# typed: true
# frozen_string_literal: true

class Businesses::TwoFactorRequirementController < Businesses::BusinessController
  class BusinessTwoFactorRequirementValidationError < StandardError; end

  before_action :business_owner_required
  before_action :sudo_filter, only: :update
  before_action :updating_two_factor_requirement_required, only: :show

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot, only: [:show], optional: true

  def show
    respond_to do |format|
      format.html do
        render partial: "businesses/settings/security/two_factor/requirement_checkbox", locals: {
          business: this_business,
        }
      end
    end
  end

  def update
    required = params[:two_factor_required]&.to_s
    validate_setting value: required, valid_values: %w(enabled no_policy)

    secure_methods =
      params[:two_factor_secure_methods_required]&.to_s || "no_policy"
    validate_setting value: secure_methods, valid_values: %w(enabled no_policy)

    if !GitHub.auth.two_factor_authentication_enabled?
      flash[:error] = "Built-in two-factor authentication is not enabled on your instance."
      return redirect_to settings_security_enterprise_path(this_business)
    elsif GitHub.auth.builtin_auth_fallback?
      flash[:error] = "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed."
      return redirect_to settings_security_enterprise_path(this_business)
    end

    if this_business.updating_two_factor_requirement?
      flash[:error] = "The enterprise account two factor requirement is being updated. Please wait until the update is completed before changing the setting."
      return redirect_to settings_security_enterprise_path(this_business)
    end

    message = ""
    if required == "no_policy"
      this_business.disable_two_factor_required(actor: current_user, log_event: true)
      this_business.allow_insecure_two_factor_methods(actor: current_user, log_event: true)
      EnforceTwoFactorRequirementOnBusinessJob.clear_status!(this_business)
      message = "Disabled two-factor authentication requirement policy. Individual organizations may enable or disable two-factor authentication."
    else
      disallow_insecure_methods = secure_methods == "enabled"
      disallowed_methods = disallow_insecure_methods ? [Configurable::TwoFactorDisallowedMethods::INSECURE] : []

      begin
        validate_actor!(disallowed_methods)
      rescue BusinessTwoFactorRequirementValidationError => e
        flash[:error] = e.message
        return redirect_to settings_security_enterprise_path(this_business)
      end

      if this_business.two_factor_requirement_enabled?
        if disallow_insecure_methods
          this_business.disallow_insecure_two_factor_methods(actor: current_user)
        else
          this_business.allow_insecure_two_factor_methods(actor: current_user, log_event: true)
        end
        message = "Updating two-factor authentication requirement."
      else
        EnforceTwoFactorRequirementOnBusinessJob.perform_later(this_business, current_user, disallowed_methods: disallowed_methods)
        message = "Enabling two-factor authentication requirement."
      end
    end

    redirect_to settings_security_enterprise_path(this_business), notice: message
  end

  private

  def validate_actor!(disallowed_methods)
    if !current_user.two_factor_authentication_enabled?
      raise BusinessTwoFactorRequirementValidationError, "Two-factor authentication must be enabled on your personal account to modify it for the enterprise account."
    end

    if current_user.has_any_given_2fa_methods_configured?(disallowed_methods)
      raise BusinessTwoFactorRequirementValidationError, "SMS two-factor authentication must be disabled on your personal account before the secure methods policy can be enabled."
    end
  end
end
