# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EnterpriseAccessVerification
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include GitHub::ResilienceMixin

      PROXY_SECURITY_HEADER_UNSATISFIED = "proxy_security_header_unsatisfied"

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
          return :no if Apps::Privileged.capable?(:skip_enterprise_access_verification_cap, app: actor)
        end

        # skip the policy if business slug was not defined in the "sec-GitHub-allowed-enterprise" header
        return :no unless business_security_header

        # skip to enforceable if business slug is not valid, will be handled by the policy enforcement
        business_from_header = business_from_security_header(business_security_header)
        return :yes unless business_from_header

        # not applicable for non-enterprise managed business
        return :no unless business_from_header.enterprise_managed?
        return :no unless business_from_header.proxy_security_header_enabled?

        :yes
      end

      # Satisfied if the actor belongs to the same enterprise as the current business from the "sec-GitHub-allowed-enterprise" header
      def enterprise_access_verification_satisfied(resource:, target_provider:)
        business_from_header = business_from_security_header(business_security_header)
        return :no unless business_from_header

        return :yes if anonymous_request?

        current_actor = nil
        with_database_error_fallback(fallback: :no) do
          current_actor = actor || authenticated_key
          return :yes if business_for(current_actor) == business_from_header
        end

        instrument_proxy_security_header_unsatisfied(business_from_header, current_actor)

        :no
      end

      private

      def business_security_header
        request_access_security_header
      end

      def business_from_slug(slug)
        Business.find_by(slug: slug)
      end

      def integer?(value)
        begin
          Integer value
        rescue
          return false
        end
        true
      end

      def business_from_security_header(header_value)
        return unless header_value
        return @business if defined?(@business)

        @business = if integer?(header_value)
          Business.find_by(id: header_value.to_i)
        else
          Business.find_by(slug: header_value)
        end
      end

      def anonymous_request?
        anonymous? && !authenticated_through_integration?
      end

      def instrument_proxy_security_header_unsatisfied(business, current_actor)
        actor = case current_actor
        when IntegrationInstallation
          current_actor.integration.bot
        when Integration
          current_actor.bot
        when PublicKey
          current_actor.repository&.owner
        else
          current_actor
        end

        payload = {
          actor: actor,
          actor_ip: actor_ip
        }

        business.instrument PROXY_SECURITY_HEADER_UNSATISFIED, payload
      end
    end
  end
end
