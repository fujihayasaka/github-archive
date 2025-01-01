# typed: true
# frozen_string_literal: true

# The LegacyPersonalAccessTokensPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource is not using a legacy PAT (OauthAccess).
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::LegacyPersonalAccessTokensPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::LegacyPersonalAccessTokens

  def legacy_personal_access_tokens_enforce(target)
    raise Platform::Errors::Execution.new("Personal access tokens (classic)", "Access to #{target.display_login} with a personal access token (classic) is forbidden")
  end
end
