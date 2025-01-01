# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EnterpriseAccessVerification
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include GitHub::ResilienceMixin

      # Applicable on EMUS dotcom only
      # enforce CAP policy that actor's enterprise matches enterprise slug in a "sec-GitHub-allowed-enterprise" header
      def enterprise_access_verification_applicable(resource:, target_provider:)
        return :no if GitHub.multi_tenant_enterprise?
        return :no if GitHub.enterprise?

        # skipped for site admins
        return :no if actor.instance_of?(User) && actor.site_admin?
        # skipped for internal applications with the skip_enterprise_access_verification_cap capability enabled
        # skip_enterprise_access_verification_cap is currently set to false for all internal applications
        if actor.is_a?(Integration) || actor.is_a?(OauthApplication)
          return :no if Apps::Internal.capable?(:skip_enterprise_access_verification_cap, app: actor)
        end

        # skip the policy if business slug was not defined in the "sec-GitHub-allowed-enterprise" header
        return :no unless business_slug_header

        # skip to enforceable if business slug is not valid, will be handled by the policy enforcement
        business_from_header = business_from_slug(business_slug_header)
        return :yes unless business_from_header

        # not applicable for non-enterprise managed business
        return :no unless business_from_header.enterprise_managed?
        return :no unless business_from_header.feature_enabled?(:enterprise_access_verification_beta)

        :yes
      end

      # Satisfied if the actor belongs to the same enterprise as the current business from the "sec-GitHub-allowed-enterprise" header
      def enterprise_access_verification_satisfied(resource:, target_provider:)
        business_from_header = business_from_slug(business_slug_header)
        return :no unless business_from_header

        return :yes if anonymous_request?

        with_database_error_fallback(fallback: :no) do
          current_actor = actor || authenticated_key
          return :yes if business_for(current_actor) == business_from_header
        end

        :no
      end

      private

      def business_slug_header
        request_access_security_header
      end

      def business_from_slug(slug)
        Business.find_by(slug: slug)
      end

      def anonymous_request?
        anonymous? && !authenticated_through_integration?
      end
    end
  end
end
