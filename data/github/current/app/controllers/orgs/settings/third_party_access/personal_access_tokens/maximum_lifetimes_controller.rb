# typed: true
# frozen_string_literal: true

module Orgs::Settings::ThirdPartyAccess::PersonalAccessTokens
  class MaximumLifetimesController < Orgs::Controller
    include ControllerMethods

    before_action :organization_admin_required
    before_action :require_feature_flags
    before_action :sudo_filter

    def update
      if require_pat_to_expire_enabled?
        type, message = set_maximum_lifetime_configuration(pat_type, access_token_expiration_limit)
      else
        type, message = disable_maximum_lifetime_configuration(pat_type)
      end

      flash[type] = message

      redirect_to settings_path_with_tab
    rescue KeyError
      flash[:error] = "Invalid Personal Access Token type"
      redirect_to settings_path_with_tab
    end

    private

    def settings_path_with_tab
      if pat_type == ProgrammaticAccessTokenType::Classic
        settings_org_personal_access_tokens_path(current_organization, tab: "classic")
      else
        settings_org_personal_access_tokens_path(current_organization)
      end
    end

    def access_token_expiration_limit
      params[:organization][:fine_grained_personal_access_token_expiration_limit] == "custom" ? params[:organization][:custom_fine_grained_personal_access_token_expiration_limit].to_i : params[:organization][:fine_grained_personal_access_token_expiration_limit].to_i
    end

    def require_pat_to_expire_enabled?
      org_business = current_organization.business

      # Determine if the business enforces a personal access token expiration limit
      business_enforces_expiration_limit = org_business.present? &&
        ProgrammaticAccessTokenLifetimeConfiguration.new(org_business, pat_type).personal_access_token_expiration_limit_enabled?

      # Check if the organization requires personal access tokens to expire or if the business enforces it
      requires_pat_expiration = params[:organization][:require_pat_to_expire] == "1" || business_enforces_expiration_limit
    end

    def pat_type
      ProgrammaticAccessTokenType.deserialize(params[:organization][:pat_type])
    end

    def require_feature_flags
      return render_404 unless current_organization.patsv2_enabled?
      return render_404 unless current_organization.business&.feature_enabled?(:personal_access_token_expiration_limit) || current_organization.feature_enabled?(:personal_access_token_expiration_limit)
      render_404 unless current_organization.business&.feature_enabled?(:personal_access_token_org_expiration_ui) || current_organization.feature_enabled?(:personal_access_token_org_expiration_ui)
    end

    sig { params(pat_type: ProgrammaticAccessTokenType, maximum_lifetime_days: Integer).returns([Symbol, String]) }
    def set_maximum_lifetime_configuration(pat_type, maximum_lifetime_days)
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(current_organization, pat_type)
      lifetime_configuration.set_maximum_lifetime_configuration(current_user, maximum_lifetime_days)
      [:notice, "Personal access tokens expiration policy updated"]

    rescue Configurable::PersonalAccessTokenExpirationLimit::ConfigurationError => e
      [:error, e.message]
    end

    sig { params(pat_type: ProgrammaticAccessTokenType).returns([Symbol, String]) }
    def disable_maximum_lifetime_configuration(pat_type)
      lifetime_configuration = ProgrammaticAccessTokenLifetimeConfiguration.new(current_organization, pat_type)
      lifetime_configuration.disable_personal_access_token_expiration_limit(current_user)

      [:notice, "Personal access tokens expiration policy disabled"]
    end
  end
end
