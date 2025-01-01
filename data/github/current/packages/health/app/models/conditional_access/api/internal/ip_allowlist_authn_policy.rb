# typed: true
# frozen_string_literal: true

# The IpAllowlistAuthnPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has IP Allowlist enabled.
#
# This is the GraphQL specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Internal::IpAllowlistAuthnPolicy
  extend T::Helpers

  requires_ancestor { Object }

  include ::ConditionalAccess::Policy::IpAllowlist

  def ip_allowlist_enforce(target)
    raise Platform::Errors::Execution.new("IP_ALLOW_LIST", "IP not allowed for #{target}")
  end
end
