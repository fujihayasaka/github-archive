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
      issuer: "https://github.com",
      jwks_uri: "https://github.com/login/oauth/.well-known/jwks",
      subject_types_supported: %w[public],
      response_types_supported: %w[code id_token],
      claims_supported: response.claims,
      id_token_signing_alg_values_supported: response.algorithms,
      scopes_supported: response.scopes,
    }

    render json: msg, status: :ok
  end

  def jwks # rubocop:todo GitHub/UseRestfulActions
    identity_manager = ::GitHub::Authnd::identity_manager("github/account_login")

    response = identity_manager.jwks

    render json: response, status: :ok
  end
end
