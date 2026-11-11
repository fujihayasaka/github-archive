# typed: true
# frozen_string_literal: true

class OauthIdentityController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:openid_configuration, :jwks]

  def openid_configuration # rubocop:todo GitHub/UseRestfulActions
    identity_manager = ::GitHub::Authnd::identity_manager("github/account_login")

    response = identity_manager.discovery_document

    msg = {
      issuer: issuer,
      jwks_uri: jwks_uri,
      subject_types_supported: %w[public],
      response_types_supported: issuer_fix_enabled? ? %w[code] : %w[code id_token],
      claims_supported: response.claims,
      id_token_signing_alg_values_supported: response.algorithms,
      scopes_supported: response.scopes, # Still incorrect until https://github.com/github/authnd/pull/4074
    }

    if issuer_fix_enabled?
      msg[:authorization_endpoint] = authorization_endpoint
      msg[:token_endpoint] = token_endpoint
      msg[:response_modes_supported] = %w[query]
      if dynamic_issuer_enabled?
        msg[:grant_types_supported] = grant_types_supported
        msg[:device_authorization_endpoint] = device_authorization_endpoint
        msg[:service_documentation] = "#{GitHub.developer_help_url}/apps/creating-github-apps/registering-a-github-app/registering-a-github-app"
      end
    end

    render json: msg, status: :ok
  end

  def jwks # rubocop:todo GitHub/UseRestfulActions
    identity_manager = ::GitHub::Authnd::identity_manager("github/account_login")

    response = identity_manager.jwks

    render json: response, status: :ok
  end

  private

  def dynamic_issuer_enabled?
    FeatureFlag.vexi.enabled?(:oidc_discovery_dynamic_issuer, default: false)
  end

  def authorization_endpoint
    "#{issuer}/authorize"
  end

  def token_endpoint
    "#{issuer}/access_token"
  end

  def grant_types_supported
    %w[authorization_code refresh_token urn:ietf:params:oauth:grant-type:device_code]
  end

  def device_authorization_endpoint
    "#{GitHub.url}/login/device/code"
  end

  def issuer
    if issuer_fix_enabled?
      if dynamic_issuer_enabled? # Can only ship once authnd is fixed https://github.com/github/authnd/pull/4074
        "#{GitHub.url}/login/oauth"
      else
        "https://github.com/login/oauth"
      end
    else
      "https://github.com"
    end
  end

  def jwks_uri
    if issuer_fix_enabled? && dynamic_issuer_enabled?
      "#{GitHub.url}/login/oauth/.well-known/jwks"
    else
      "https://github.com/login/oauth/.well-known/jwks"
    end
  end

  def issuer_fix_enabled?
    FeatureFlag.vexi.enabled?(:oidc_metadata_issuer_fix, default: false)
  end
end
