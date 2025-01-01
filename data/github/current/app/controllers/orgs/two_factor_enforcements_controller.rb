# typed: true
# frozen_string_literal: true

module Orgs
  class TwoFactorEnforcementsController < Controller
    before_action :sudo_filter, except: :show
    before_action :organization_admin_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Authnd,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show], optional: true

    def update
      if this_organization.can_disallow_two_factor_methods?
        required = params[:two_factor_required]&.to_s
        validate_setting value: required, valid_values: %w(enabled no_policy)

        secure_methods =
          if this_organization.can_disallow_two_factor_methods?
            params[:two_factor_secure_methods_required]&.to_s
          end || "no_policy"
        validate_setting value: secure_methods, valid_values: %w(enabled no_policy)

        if !GitHub.auth.two_factor_authentication_enabled?
          flash[:error] = "Built-in two-factor authentication is not enabled on your instance."
          return redirect_to settings_org_security_path(this_organization)
        elsif GitHub.auth.builtin_auth_fallback?
          flash[:error] = "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed."
          return redirect_to settings_org_security_path(this_organization)
        elsif !current_user.two_factor_authentication_enabled?
          flash[:error] = "Two-factor authentication must be enabled on your personal account to modify it for the organization."
          return redirect_to settings_org_security_path(this_organization)
        end

        if this_organization.enforcing_two_factor_requirement?
          flash[:error] = "The organization two factor requirement is being updated.  Please wait until the update is completed before changing the setting."
          return redirect_to settings_org_security_path(this_organization)
        end

        required_policy_from_business = this_organization.two_factor_required_policy?
        secure_policy_from_business = this_organization.two_factor_disallowed_methods_policy?
        enabled_2fa_required = required == "enabled"
        enabled_secure_methods = secure_methods == "enabled"
        changed_2fa_required = this_organization.two_factor_requirement_enabled? != enabled_2fa_required
        changed_secure_methods = this_organization.insecure_two_factor_methods_disallowed? != enabled_secure_methods

        # Make sure the user isnt trying to change a policy that is enforced by the business
        if changed_2fa_required && required_policy_from_business
          flash[:error] = "Cannot change two-factor authentication requirement because it is enabled by the enterprise."
          return redirect_to settings_org_security_path(this_organization)
        elsif changed_secure_methods && secure_policy_from_business
          flash[:error] = "Cannot change two-factor authentication secure method requirement because it is enabled by the enterprise."
          return redirect_to settings_org_security_path(this_organization)
        end

        unless changed_2fa_required || changed_secure_methods
          flash[:error] = "No changes made to two-factor policy. Please make a change before saving."
          return redirect_to settings_org_security_path(this_organization)
        end

        message = ""
        # Update the 2FA requirement policy if required
        if changed_2fa_required
          if enabled_2fa_required
            disallowed_methods = enabled_secure_methods ? [Configurable::TwoFactorDisallowedMethods::INSECURE] : []
            EnforceTwoFactorRequirementOnOrganizationJob.perform_later(this_organization, current_user, disallowed_methods: disallowed_methods)
            message = "Enabling two-factor authentication requirement."
          else
            this_organization.disable_two_factor_required(actor: current_user, log_event: true)
            this_organization.allow_insecure_two_factor_methods(actor: current_user, log_event: true)
            EnforceTwoFactorRequirementOnOrganizationJob.clear_status!(this_organization) # Only for development, check happens in function
            message = "Disabled two-factor authentication requirement policy."
          end

          return redirect_to settings_org_security_path(this_organization), notice: message
        end

        if changed_secure_methods
          if enabled_secure_methods
            this_organization.disallow_insecure_two_factor_methods(actor: current_user)
            message = "Enabled secure two-factor method authentication requirement."
          else
            this_organization.allow_insecure_two_factor_methods(actor: current_user, log_event: true)
            message = "Disabled secure two-factor method authentication requirement."
          end
        end

        redirect_to settings_org_security_path(this_organization), notice: message
      else
        if !GitHub.auth.two_factor_authentication_enabled?
          flash[:error] = "Built-in two-factor authentication is not enabled on your instance."
        elsif this_organization.two_factor_required_policy?
          flash[:error] = "Two factor authentication is required for all organizations in this enterprise."
        elsif enabling? == this_organization.two_factor_requirement_enabled?
          if enabling?
            flash[:notice] = "Two-factor authentication requirement already enabled."
          else
            flash[:notice] = "Two-factor authentication requirement already disabled."
          end
        elsif enabling? && confirmed?
          EnforceTwoFactorRequirementOnOrganizationJob.perform_later(this_organization, current_user)
          flash[:notice] = "Enabling two-factor authentication requirement."
        elsif enabling?
          flash[:error] = "Failed to enable two-factor authentication requirement. Please try again."
        else
          GitHub.dogstats.increment "organization", tags: ["subject:two_factor_requirement", "action:disable"]

          flash[:notice] = "Disabled two-factor authentication requirement."
          this_organization.disable_two_factor_requirement(log_event: true, actor: current_user)
        end

        redirect_to settings_org_security_path(this_organization)
      end
    end

    def show
      status = this_organization.enforce_two_factor_requirement_job_status

      return render_404 unless status.present?

      if status.finished?
        options = {
          organization: this_organization,
          current_user: current_user,
        }

        if status.error?
          flash[:error] = "Failed to enable two-factor authentication requirement. Please try again."
        end

        if status.success?
          flash[:notice] = "Enabled two-factor authentication requirement."
        end

        respond_to do |format|
          format.html do
            if params["type"] == "secure"
              render partial: "orgs/security_settings/two_factor/secure_methods_checkbox",
                locals: { view: create_view_model(Orgs::SecuritySettings::IndexView, options) }
            else
              render partial: "orgs/security_settings/two_factor/requirement_checkbox",
                locals: { view: create_view_model(Orgs::SecuritySettings::IndexView, options) }
            end
          end
        end
      else
        head 202
      end
    end

    private

    def enabling?
      params[:two_factor_requirement] == "on"
    end

    def confirmed?
      return true unless needs_confirmation?

      params[:confirmation].try(:downcase) == this_organization.display_login.downcase
    end

    def needs_confirmation?
      # restore this line after https://github.com/github/authorization/issues/4526
      # !this_organization.members_without_2fa_allowed? && this_organization.affiliated_users_with_two_factor_disabled_exist?

      # if there are no violations, we don't need to confirm
      return false unless this_organization.affiliated_users_with_two_factor_disabled_exist?

      # if there are violations, we need to confirm if:
      # * feature disabled                             (all violators will be removed)
      # * feature enabled and violations are OCs       (OCs will be removed)
      return true unless this_organization.members_without_2fa_allowed?
      return true if this_organization.outside_collaborators_with_two_factor_disabled.any?

      # otherwise, violations don't matter b/c the affected users will retain membership
      false
    end

  end
end
