# typed: strict
# frozen_string_literal: true

# The PersonalAccessTokensPolicy makes sure access to resources are only
# authorized when the user accessing a policy-protected resource is not using a
# PAT (classic) or fine-grained PAT.
#
# This is the API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::PersonalAccessTokensExpirationLimitPolicy
  extend T::Helpers

  include ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit
  include ::ConditionalAccess::Helpers::PersonalAccessTokensExpirationLimit

  requires_ancestor { ConditionalAccess::Api::Public::Enforcer }

  sig { params(target: T.any(Business, Organization)).void }
  def personal_access_tokens_expiration_limit_enforce(target)
    message = expiration_limit_exceeded_error_message(target, actor)

    # adds response body message to the Audit.context
    # this will log the message via event streaming
    Audit.context.push(response_error_message: message)

    callback.set_forbidden_message(message)
  end
end
