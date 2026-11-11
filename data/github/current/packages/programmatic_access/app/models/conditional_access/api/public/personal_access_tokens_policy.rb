# typed: true
# frozen_string_literal: true

# The PersonalAccessTokensPolicy makes sure access to resources are only
# authorized when the user accessing a policy-protected resource is not using a
# PAT (UserProgrammaticAccess).
#
# This is the API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::PersonalAccessTokensPolicy
  extend T::Helpers
  include ::ConditionalAccess::Policy::PersonalAccessTokens

  requires_ancestor { ConditionalAccess::Api::Public::Enforcer }

  def personal_access_tokens_enforce(target)
    target_name = case target
    when Organization
      target.display_login
    else
      target.name
    end

    message = <<~MSG.squish
      `#{target_name}` forbids access via a personal access token with fine-grained permissions.
      Please use a GitHub App, or an OAuth App.
    MSG

    callback.set_forbidden_message(message)
  end
end
