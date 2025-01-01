# typed: strict
# frozen_string_literal: true

# The PersonalAccessTokensExpirationLimitPolicy makes sure access to resources are only
# authorized when the user accessing a policy-protected resource is not using a
# PAT (classic) or fine-grained PAT.

# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::PersonalAccessTokensExpirationLimitPolicy
  include ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit
  include ::ConditionalAccess::Helpers::PersonalAccessTokensExpirationLimit

  extend T::Helpers

  requires_ancestor { ConditionalAccess::Api::Internal::Enforcer }

  sig { params(target: T.any(Business, Organization)).void }
  def personal_access_tokens_expiration_limit_enforce(target)
    message = expiration_limit_exceeded_error_message(target, actor)

    # adds response body message to the Audit.context
    # this will log the message via event streaming
    if target.feature_enabled?(:log_api_error_message) || (target.is_a?(Organization) && target.business&.feature_enabled?(:log_api_error_message))
      Audit.context.push(response_error_message: message)
    end

    raise Platform::Errors::Execution.new("Personal Access Tokens", message)
  end
end
