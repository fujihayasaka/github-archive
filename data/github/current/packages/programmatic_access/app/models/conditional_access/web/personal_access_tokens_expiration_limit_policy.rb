# typed: strict
# frozen_string_literal: true

# The PersonalAccessTokensExpirationLimitPolicy ensures that access to resources
# protected by this policy is only authorized when the actor is using a personal
# access token (classic or fine-grained) that complies with the enforced
# expiration limit.
#
# This is the Web (ApplicationController) specific implementation of the
# expiration-limit policy, and is meant to be used solely in that context.
module ConditionalAccess::Web::PersonalAccessTokensExpirationLimitPolicy
  extend T::Helpers

  include ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit
  include ::ConditionalAccess::Helpers::PersonalAccessTokensExpirationLimit

  requires_ancestor { ConditionalAccess::Web::Enforcer }

  sig { params(target: T.any(Business, Organization)).void }
  def personal_access_tokens_expiration_limit_enforce(target)
    message = expiration_limit_exceeded_error_message(target, actor)

    # adds response body message to the Audit.context
    # this will log the message via event streaming
    Audit.context.push(response_error_message: message)

    callback.send(:render, plain: message, status: :forbidden)
  end
end
