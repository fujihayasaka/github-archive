# typed: true
# frozen_string_literal: true

# The IpAllowlistPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has an allowed originating
# IP address.
#
# This is the API specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Api::Public::IpAllowlistPolicy
  include ::ConditionalAccess::Policy::IpAllowlist
  include ::ConditionalAccess::Policy::IpAllowlistPolicyHelper

  def ip_allowlist_enforce(target)
    policy_owner = policy_owner_for_target(target)
    inject_log_data(policy_owner, T.unsafe(self).actor, T.unsafe(self).actor_ip)

    message = <<~MSG.squish
      Although you appear to have the correct authorization credentials,
      the #{policy_owner_name_and_type(policy_owner)} has an IP allow list enabled, and
      your IP address is not permitted to access this resource.
    MSG

    T.unsafe(self).callback.send(:set_forbidden_message, message)
  end

  private

  def inject_log_data(target, actor, actor_ip)
    if T.unsafe(self).callback.respond_to?(:request, true)
      request = T.unsafe(self).callback.send(:request)
      if request&.env[Rack::RequestLogger::APPLICATION_LOG_DATA]
        # Set log fields to indicate IP allow list enforcement
        request.env[Rack::RequestLogger::APPLICATION_LOG_DATA].merge!({
          ip_allow_list_policy_unsatisfied: true,
          ip_allow_list_policy_evaluated_ip: actor_ip,
          ip_allow_list_policy_owner_id: target.id,
          ip_allow_list_policy_owner_type: target.is_a?(::Business) ? :BUSINESS : :ORG,
          ip_allow_list_policy_actor: actor.to_s,
          ip_allow_list_policy_actor_type: actor.class.name,
          ip_allow_list_policy_actor_bot: actor.try(:bot?),
        })
      end
    end
  end

  def policy_owner_name_and_type(policy_owner)
    if [Platform::Models::Enterprise, Business].include?(policy_owner.class)
      "`#{policy_owner}` enterprise"
    else
      "`#{policy_owner.display_login}` organization"
    end
  end
end
