# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class UserWithScopesAuthorizer < AuthorizerBase
      def authorized?(verb, options)
        request_authn_context.access_grant(verb, options).access_allowed?
      end
    end
  end
end
