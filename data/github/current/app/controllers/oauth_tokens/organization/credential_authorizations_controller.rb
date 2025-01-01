# typed: strict
# frozen_string_literal: true

class OauthTokens::Organization::CredentialAuthorizationsController < ApplicationController
  include Organization::CredentialAuthorizationsHelper

  before_action :login_required

  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    current_access = OauthAccessTokens.domain.personal_token_by_user_and_id(current_user.id, params[:id].to_i)

    return(render_404) unless current_access

    org_credential_map = if current_user.feature_flag_enabled_or_raise?(:org_credential_authorization_tracing) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      organization_credential_authorization_map_with_tracing(current_access)
    else
      organization_credential_authorization_map(current_access)
    end

    if params[:q].present?
      query = params[:q].downcase
      org_credential_map.select! { |k, _| k.display_login.downcase.include?(query) }
    end

    render(Organizations::CredentialAuthorizations::ListComponent.new(
      credential: T.cast(current_access, OauthAccess),
      org_credential_map: org_credential_map,
      experimental: params[:experimental],
    ), layout: false)
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
