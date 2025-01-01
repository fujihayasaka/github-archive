# typed: strict
# frozen_string_literal: true

module Copilot
  module Signup
    extend T::Helpers

    # Abstract away the abuse notification code we need to run to ensure organizations can
    # sign up for and continue using Copilot.
    #
    # Note that if an organization shares a payment method with a single blocked user,
    # we issue a notification but allow the organization to sign up for Copilot.
    #
    # We will only block the org if the payment method is shared with multiple blocked users.
    sig { params(actor: ::User, url: T.nilable(String), block: Proc).void }
    def ensure_signup(actor:, url:, &block)
      # We currently only need to perform auth and capture checks for organizations
      yield true and return if configurable_object.business?

      # We return early for businesses, so this is safe.
      organization = T.cast(configurable_object, ::Organization)
      copilot_organization = Copilot::Organization.new(organization)

      blocked = copilot_organization.block_if_sharing_payment_method_with_other_blocked_users!

      if blocked
        copilot_organization.send_abuse_notification(
          url: url,
          signed_up: false,
        )

        yield false and return
      end

      if copilot_organization.shares_payment_method_with_blocked_user?
        copilot_organization.send_abuse_notification(
          url: url,
          signed_up: true,
        )
      end

      yield true

      copilot_organization.schedule_auth_and_capture!(reason: "signup")

      # If the org is untrusted (e.g. on the neutral or untrusted trust tier), we'll schedule another capture to be performed
      # when the first token is generated
      is_untrusted = TrustTiers::Tier.for_billable_owner(organization).tier >= TrustTiers::Tier::NEUTRAL
      copilot_organization.schedule_auth_and_capture!(reason: "first token", pending_token: true) if is_untrusted
    end

    abstract!

    sig { abstract.returns(T.any(::Organization, ::Business)) }
    def configurable_object; end
  end
end
