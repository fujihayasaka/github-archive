# typed: true
# frozen_string_literal: true

# The IpAllowlistPolicy makes sure access to resources are only authorized
# when the user accessing a policy-protected resource has an allowed originating
# IP address.
#
# This is the ApplicationController specific implementation, and is meant to be
# used solely in that context.
module ConditionalAccess::Web::IpAllowlistPolicy
  include ::ConditionalAccess::Policy::IpAllowlist
  include ::ConditionalAccess::Policy::IpAllowlistPolicyHelper

  # ApplicationController specific enforcement implementation that shows an
  # interstitial prompting the user to connect from an allowed IP address
  #
  # target - Target for conditional access
  def ip_allowlist_enforce(target)
    policy_owner = policy_owner_for_target(target)
    inject_log_data(policy_owner, T.unsafe(self).actor)
    render_ip_forbidden_interstitial(policy_owner)
  end

  private

  ENFORCEMENT_STATUS = :forbidden

  def render_ip_forbidden_interstitial(target)
    request = T.unsafe(self).callback.send(:request)
    if request.format.try(:html?) || request.format.try(:html_fragment?)
      T.unsafe(self).callback.send(
        :render,
        ConditionalAccess::IpAllowlist::AccessForbiddenComponent.new(
          target: target,
          ip: request.remote_ip
        ),
        status: ENFORCEMENT_STATUS,
        layout: "application"
      )
    elsif request.format.try(:js?) || request.format.try(:json?)
      T.unsafe(self).callback.send(:set_static_file_csp)
      T.unsafe(self).callback.send(
        :render,
        json: { error: "Forbidden - Allowed IP required" },
        status: ENFORCEMENT_STATUS
      )
    else
      T.unsafe(self).callback.send(:set_static_file_csp)
      T.unsafe(self).callback.send(
        :render,
        plain: "Forbidden - Allowed IP required",
        status: ENFORCEMENT_STATUS
      )
    end
    nil
  end

  def inject_log_data(target, actor)
    # Set log fields to indicate IP allow list enforcement
    request = T.unsafe(self).callback.send(:request)
    log_data = T.unsafe(self).callback.send(:log_data)
    log_data.merge!({
      ip_allow_list_policy_unsatisfied: true,
      ip_allow_list_policy_evaluated_ip: request.remote_ip,
      ip_allow_list_policy_owner_id: target.id,
      ip_allow_list_policy_owner_type: target.is_a?(::Business) ? :BUSINESS : :ORG,
      ip_allow_list_policy_actor: actor.to_s,
      ip_allow_list_policy_actor_type: actor.class.name,
      ip_allow_list_policy_actor_bot: actor.try(:bot?),
    })
  end
end
