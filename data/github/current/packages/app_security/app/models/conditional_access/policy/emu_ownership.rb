# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EmuOwnership
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include Scientist

      # This method can be removed once the ConditionalAccess::Enforcer
      # inherits from the ConditionalAccess::Filter
      #
      # applicable if actor is Enterprise-managed
      def emu_ownership_applicable(resource:, target_provider:)
        return :no if GitHub.enterprise?

        return :no if anonymous?
        return :no if safe_request_method? && !GitHub.multi_tenant_enterprise?
        return :no if actor.instance_of?(User) && actor.site_admin?

        if safe_request_method? && (actor.is_a?(Integration) || actor.is_a?(OauthApplication))
          return :no if Apps::Privileged.capable?(:skip_emu_ownership_cap, app: actor)
        end

        # actor is considered part of an EMU Enterprise
        business = business_for(actor)

        return :no unless business && business.enterprise_managed_user_enabled?

        target = target_provider.target(resource)
        return :no if target == :no_target_for_conditional_access

        # Third Party Synced Apps are owned by a special non-enterprise managed org
        # these apps should be visible to all tenants in Proxima
        return :no if resource.try(:synchronized_third_party_app?)

        :yes
      end

      def emu_ownership_satisfied(resource:, target_provider:)
        emu_business = business_for(actor)
        target = target_provider.target(resource)

        # EMU (self) owned content
        return :yes if target == actor

        # EMU business, org, or user owned content (in same Business)
        return :no unless target.instance_of?(Business) || target.instance_of?(Organization) || target.instance_of?(User)
        return :yes if business_for(actor) == business_for(target)

        :no
      end

      def multiple_emu_ownership_applicable(targets, target_provider)
        targets.filter do |target|
          emu_ownership_applicable(resource: target, target_provider: target_provider) == :yes
        end
      end

      def multiple_emu_ownership_satisfied(targets, target_provider)
        result = Hash.new { |h, k| h[k] = {} }
        targets.map  do |target|
          result[target] =
          {
            # emu ownership satisfied for private resources
            private: emu_ownership_satisfied(resource: target, target_provider: target_provider) == :yes ? :satisfied : :unsatisfied,
          }
        end
        result
      end
    end
  end
end
