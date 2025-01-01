# typed: true
# frozen_string_literal: true

class Businesses::TwoFactorRequirementController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :sudo_filter, only: :update
  before_action :require_requirement_updating, only: [:show, :secure_methods]

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
    only: [:show, :secure_methods]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :secure_methods], optional: true

  def show
    respond_to do |format|
      format.html do
        render partial: "businesses/settings/security/two_factor/requirement_checkbox", locals: {
          business: this_business,
        }
      end
    end
  end

  def secure_methods # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        return render_404 unless this_business.can_disallow_two_factor_methods?

        render partial: "businesses/settings/security/two_factor/secure_methods_checkbox", locals: {
          business: this_business,
        }
      end
    end
  end

  def update
    required = params[:two_factor_required]&.to_s
    validate_setting value: required, valid_values: %w(enabled no_policy)

    secure_methods =
      if this_business.can_disallow_two_factor_methods?
        params[:two_factor_secure_methods_required]&.to_s
      end || "no_policy"
    validate_setting value: secure_methods, valid_values: %w(enabled no_policy)

    if required == "enabled" &&
       this_business.name.downcase != params[:verify]&.downcase &&
       this_business.affiliated_users_with_two_factor_disabled_exist? &&
       !this_business.can_disallow_two_factor_methods?
      flash[:error] = "You must type the name of the enterprise to confirm."
      return redirect_to settings_security_enterprise_path(this_business)
    end

    if !GitHub.auth.two_factor_authentication_enabled?
      flash[:error] = "Built-in two-factor authentication is not enabled on your instance."
      return redirect_to settings_security_enterprise_path(this_business)
    elsif GitHub.auth.builtin_auth_fallback?
      flash[:error] = "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed."
      return redirect_to settings_security_enterprise_path(this_business)
    end

    if this_business.updating_two_factor_requirement?
      flash[:error] = "The enterprise account two factor requirement is being updated.  Please wait until the update is completed before changing the setting."
      return redirect_to settings_security_enterprise_path(this_business)
    end

    message = ""
    if required == "no_policy"
      this_business.disable_two_factor_required(actor: current_user, log_event: true)
      this_business.allow_insecure_two_factor_methods(actor: current_user, log_event: true) if this_business.can_disallow_two_factor_methods?
      EnforceTwoFactorRequirementOnBusinessJob.clear_status!(this_business)
      message = "Disabled two-factor authentication requirement policy. Individual organizations may enable or disable two-factor authentication."
    else
      if !current_user.two_factor_authentication_enabled?
        flash[:error] = "Two-factor authentication must be enabled on your personal account to require it for the enterprise account."
        return redirect_to settings_security_enterprise_path(this_business)
      else
        count = this_business.organizations_can_enable_two_factor_requirement(false).count
        if count > 0
          flash[:error] = "Enforcing two-factor authentication would remove all admins from #{count} #{"organization".pluralize(count)}."
          return redirect_to settings_security_enterprise_path(this_business)
        end
      end

      disallow_insecure_methods = secure_methods == "enabled"
      if this_business.two_factor_requirement_enabled?
        if disallow_insecure_methods
          this_business.disallow_insecure_two_factor_methods(actor: current_user)
        else
          this_business.allow_insecure_two_factor_methods(actor: current_user, log_event: true)
        end
        message = "Updating two-factor authentication requirement."
      else
        disallowed_methods = disallow_insecure_methods ? [Configurable::TwoFactorDisallowedMethods::INSECURE] : []
        EnforceTwoFactorRequirementOnBusinessJob.perform_later(this_business, current_user, disallowed_methods: disallowed_methods)
        message = "Enabling two-factor authentication requirement."
      end
    end

    redirect_to settings_security_enterprise_path(this_business), notice: message
  end

  private

  def require_requirement_updating
    status = this_business.enforce_two_factor_requirement_job_status

    return render_404 unless status.present?
    if this_business.updating_two_factor_requirement?
      head 202
    end
  end
end
