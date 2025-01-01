# typed: true
# frozen_string_literal: true

# The TwoFactorAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has 2FA enabled.
#
# This is the API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::TwoFactorAuthnPolicy
  extend T::Helpers
  requires_ancestor { ConditionalAccess::Enforcer }

  include ::ConditionalAccess::Policy::TwoFactorAuthn
  include TwoFactorHelper

  def two_factor_enforce(target)
    # could be a Business or an Organization
    target_name = target.respond_to?(:display_login) ? target.display_login : target.name
    disallowed_methods = target.get_two_factor_disallowed_methods

    message = String.new
    if disallowed_methods.any?
      message = <<~MSG.squish
        `#{target_name}` requires everyone in the organization to enable two-factor authentication with any of the following methods:
        #{TwoFactorHelper::display_two_factor_methods_text_list(target.get_two_factor_allowed_methods)}.
        Only secure 2FA methods are allowed. Please remove SMS if configured as it is not considered secure.
        You will not be able to access this resource until your two-factor authentication settings are compliant.
      MSG
    else
      message = <<~MSG.squish
        `#{target_name}` requires everyone in the organization to enable two-factor authentication.
        You will not be able to access this resource until you enable two-factor authentication.
      MSG
    end

    callback.send(:set_forbidden_message, message)
  end
end
