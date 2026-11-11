# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module TenantVerification
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include GitHub::ResilienceMixin

      # Applicable on Proxima only
      def tenant_verification_applicable(resource:, target_provider:)
        return :no unless GitHub.multi_tenant_enterprise?
        return :no if actor.instance_of?(User) && actor.site_admin?

        current_tenant = GitHub::CurrentTenant.get
        return :no unless current_tenant

        if actor.is_a?(Integration) || actor.is_a?(OauthApplication)
          return :no if Apps::Privileged.capable?(:skip_tenant_verification_cap, app: actor)
          return :no if ProximaAppSynchronization.synchronized_third_party?(actor)
        end

        :yes
      end

      # Satisfied if the actor belongs to the same tenant as the current tenant
      def tenant_verification_satisfied(resource:, target_provider:)
        current_tenant = GitHub::CurrentTenant.get
        return :yes unless current_tenant

        return :no if anonymous_request?

        with_database_error_fallback(fallback: :no) do
          current_actor = actor || authenticated_key
          return :yes if business_for(current_actor) == current_tenant
        end

        :no
      end

      private

      def anonymous_request?
        anonymous? && !authenticated_through_integration?
      end
    end
  end
end
