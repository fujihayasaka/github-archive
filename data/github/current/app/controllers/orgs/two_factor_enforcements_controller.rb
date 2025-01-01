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
            render partial: "orgs/security_settings/two_factor_enforcement_checkbox",
              locals: { view: create_view_model(Orgs::SecuritySettings::IndexView, options) }
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
      return true unless needs_enforced?

      params[:confirmation].try(:downcase) == this_organization.display_login.downcase
    end

    def needs_enforced? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @needs_enforced if defined?(@needs_enforced)
      @needs_enforced = !this_organization.members_without_2fa_allowed? && this_organization.affiliated_users_with_two_factor_disabled_exist?
    end

  end
end
