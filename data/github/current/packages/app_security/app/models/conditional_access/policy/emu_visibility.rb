# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EmuVisibility
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include GitHub::ResilienceMixin

      # Applicable if the resource is enterprise-managed
      def emu_visibility_applicable(resource:, target_provider:)
        return :no if GitHub.enterprise?

        target = target_provider.target(resource)
        return :no if target == :no_target_for_conditional_access
        return :no if actor.instance_of?(User) && actor.site_admin?

        # Third Party Synced Apps are owned by a special non-enterprise managed org
        # these apps should be visible to all tenants in Proxima
        return :no if resource.try(:synchronized_third_party_app?)

        # in proxima all of the resources are a subject to this policy
        # no point of checking if the target is enterprise managed
        return :yes if GitHub.multi_tenant_enterprise?
        return :no unless enterprise_managed?(target)

        :yes
      end

      # Satisfied if the actor belongs to the same enterprise-managed business as the resource
      def emu_visibility_satisfied(resource:, target_provider:)
        return :no if anonymous? && !authenticated_through_integration?

        target = target_provider.target(resource)


        # authentication is done through an integration
        if actor.instance_of?(Integration) && authenticated_through_integration?
          # yes if the integration is installed on the resource
          case target
          when Organization, Business, User
            return :yes if IntegrationInstallation.where(target: target, integration: actor).exists?
          end

          # yes when the integration is accessing itself
          return :yes if actor == resource

          # no if the integration is not installed on the resource
          return :no
        end

        with_database_error_fallback(fallback: :no) do
          return :no if target.is_a?(User) && target.is_enterprise_managed? && !target.enterprise_managed_business

          current_actor = actor || authenticated_key
          return :yes if business_for(current_actor) == business_for(target)

          :no
        end
      end
    end
  end
end
