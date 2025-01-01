# typed: strict
# frozen_string_literal: true

module OauthAccessTokens
  extend GH::Domain::Registration

  register_domain OauthAccessTokens::Domain
end
