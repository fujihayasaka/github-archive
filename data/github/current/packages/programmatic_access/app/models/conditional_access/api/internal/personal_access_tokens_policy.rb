# typed: true
# frozen_string_literal: true

# The PersonalAccessTokensPolicy makes sure access to resources are only
# authorized when the user accessing a policy-protected resource is not using a
# PAT (UserProgrammaticAccess).

# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::PersonalAccessTokensPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::PersonalAccessTokens

  def personal_access_tokens_enforce(target)
    raise Platform::Errors::Execution.new("Fine-grained personal access tokens", "Access to #{target.display_login} with a fine-grained personal access token is forbidden")
  end
end
