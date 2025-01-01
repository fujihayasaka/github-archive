# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies
  class MaximumLifetimesController < Businesses::BusinessController
    include ControllerMethods

    before_action :business_owner_required
    before_action :sudo_filter_unless_turbo_requested

    def update
      if params[:business][:confirm].present?
        if user_not_confirmed_exemption?
          flash[:error] = "You must confirm that you do not want to exempt enterprise administrators from this policy."
          return redirect_to_pat_settings
        end

        if require_pat_to_expire_enabled?
          type, message = set_maximum_lifetime_configuration(this_business, current_user, pat_type, access_token_expiration_limit, exempt_administrators?, exempt_missing_issue_date?)
        else
          type, message = disable_maximum_lifetime_configuration(this_business, current_user, pat_type)
        end

        flash[type] = message

        redirect_to_pat_settings
      else
        render partial: "businesses/personal_access_token_policies/maximum_lifetime_confirmation_dialog"
      end
    rescue KeyError
      flash[:error] = "Invalid Personal Access Token type"
      redirect_to settings_personal_access_tokens_enterprise_path(this_business)
    end

    private

    helper_method :organizations_to_confirm_changes, :access_token_expiration_limit, :require_pat_to_expire_enabled?, :exempt_administrators?, :exempt_missing_issue_date?, :pat_type, :show_emu_classic_pat_warning?

    def user_not_confirmed_exemption?
      show_emu_classic_pat_warning? && !exempt_administrators? && params[:business][:confirm_warning] != "1"
    end

    def access_token_expiration_limit
      params[:business][:fine_grained_personal_access_token_expiration_limit] == "custom" ? params[:business][:custom_fine_grained_personal_access_token_expiration_limit].to_i : params[:business][:fine_grained_personal_access_token_expiration_limit].to_i
    end

    def require_pat_to_expire_enabled?
      params[:business][:require_pat_to_expire] == "1"
    end

    def exempt_administrators?
      params[:business][:exempt_administrators] == "1"
    end

    def exempt_missing_issue_date?
      params[:business][:exempt_missing_issue_date] == "1"
    end

    def pat_type
      ProgrammaticAccessTokenType.deserialize(params[:business][:pat_type])
    end

    def organizations_to_confirm_changes
      return [] unless require_pat_to_expire_enabled?

      @organizations_to_confirm_changes ||= ProgrammaticAccessTokenLifetimeConfiguration.business_organizations_exceeding_limit(this_business, pat_type, access_token_expiration_limit)
    end

    def show_emu_classic_pat_warning?
      return false unless this_business.enterprise_managed?

      require_pat_to_expire_enabled? && pat_type == ProgrammaticAccessTokenType::Classic && !exempt_administrators?
    end

    def sudo_filter_unless_turbo_requested
      return true if turbo_frame_request?

      perform_sudo_filter
    end

    def redirect_to_pat_settings
      if pat_type == ProgrammaticAccessTokenType::Classic
        redirect_to settings_classic_personal_access_tokens_enterprise_path(this_business)
      else
        redirect_to settings_personal_access_tokens_enterprise_path(this_business)
      end
    end
  end
end
