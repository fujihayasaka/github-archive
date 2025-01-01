# typed: strict
# frozen_string_literal: true

class OauthTokens::Organization::CredentialAuthorizationsController < ApplicationController
  extend T::Sig

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

  preload_features [:cap_pats_policy_enforcement], only: [:index]

  sig { void }
  def index
    current_access = current_user.oauth_accesses.personal_tokens.find_by(id: params[:id])
    return(render_404) unless current_access

    org_credential_map = if current_user.feature_enabled?(:org_credential_authorization_tracing)
      organization_credential_authorization_map_with_tracing(current_access)
    else
      organization_credential_authorization_map(current_access)
    end

    if params[:q].present?
      query = params[:q].downcase
      org_credential_map.select! { |k, _| k.display_login.downcase.include?(query) }
    end

    render(Organizations::CredentialAuthorizations::ListComponent.new(
      credential: current_access,
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
