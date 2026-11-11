# typed: true
# frozen_string_literal: true

# The LegacyPersonalAccessTokensPolicy makes sure access to resources are only
# authorized when the user accessing a policy-protected resource is not using a
# legacy PAT (OauthAccess).
#
# This is the Web (ApplicationController) specific implementation, and is meant
# to be used solely in that context.
module ConditionalAccess::Web::LegacyPersonalAccessTokensPolicy
  extend T::Helpers
  include ::ConditionalAccess::Policy::LegacyPersonalAccessTokens

  requires_ancestor { ConditionalAccess::Web::Enforcer }

  def legacy_personal_access_tokens_enforce(target)
    target_name = target.respond_to?(:display_login) ? target.display_login : target.name

    message = <<~MSG.squish
      `#{target_name}` forbids access via a personal access token (classic).
      Please use a GitHub App, OAuth App, or a personal access token with fine-grained permissions.
    MSG

    callback.send(:render, plain: message, status: :forbidden)
  end
end
