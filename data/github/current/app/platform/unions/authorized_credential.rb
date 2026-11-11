# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class AuthorizedCredential < Platform::Unions::Base
      description "Types of credentials that can be granted access to protected resources"

      visibility :under_development

      possible_types(
        Objects::PublicKey,
        Objects::OauthAccess,
      )
    end
  end
end
