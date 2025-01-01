# typed: true
# frozen_string_literal: true

# The IpAllowlistPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has an allowed originating
# IP address.
#
# This is the GitAuth specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::GitAuth::IpAllowlistPolicy
  include ::ConditionalAccess::Policy::IpAllowlist
end
