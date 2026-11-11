# typed: false
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EnterpriseAccessVerification
      include ConditionalAccess::Policy::EmuPoliciesHelper
      include GitHub::ResilienceMixin

      PROXY_SECURITY_HEADER_UNSATISFIED = "proxy_security_header_unsatisfied"

      # Allowlist of legacy enterprise slugs for observability logging
      LEGACY_ENTERPRISE_SLUGS = %w[
        ktdev
        prudential-financial
        bloomberg-eng
        cfh-emu
        ee2
        fitch
        poalim
        humana-inc-emu
        mufgamericas
        emirates-nbd-emu
        haeai
        ebazy1
        zempot-emu
        bofa-emu
        bofa-eden
        tcbsgh
        poscodx
        mobis
        fastretailing
        citadelgroup
        cigna-group-internal
        colpipe
        tcspocwithghec
        zs-associates-emu
        yuantacopilotgo
        sercomm-emu
        citizensbank
        hong-kong-jockey-club
        synopsys-emu
        cfh
        peoplefirstau
        naxo
        nuclea
        buut
        bpclit
        citadel2
        cuscal
        icra-limited
        afado
        whalerockcapital
        alcority-emu
        pagseguro-uol
        vanguard-emu
        wipro
        deutsche-bank-ag
        edelweiss-global-markets
        fcb-itsa
        fire1ce
        tmlconnected
      ].freeze

      MAX_BUSINESSES_IN_HEADER = 20

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

        business_identifiers = business_security_header.to_s.split(",").map(&:strip).reject(&:empty?)
        # applicable when header is empty, which will be blocked as part of satisfied check
        return :yes if business_identifiers.empty?

        # applicable when header contains more than 20 business identifiers, which will be blocked as part of satisfied check
        return :yes if business_identifiers.length > MAX_BUSINESSES_IN_HEADER

        businesses_from_header = businesses_from_security_header(business_identifiers)
        # applicable when header contains invalid business identifiers, which will be blocked as part of satisfied check
        return :yes if businesses_from_header.empty?

        # inapplicable when header does not contain a business that is enterprise managed
        return :no unless businesses_from_header.any?(&:enterprise_managed?)

        # inapplicable when header does not contain a business with proxy security enabled
        return :no unless businesses_from_header.any?(&:proxy_security_header_enabled?)

        # otherwise applicable
        :yes
      end

      # Satisfied if the actor belongs to the same enterprise as the current business from the "sec-GitHub-allowed-enterprise" header
      def enterprise_access_verification_satisfied(resource:, target_provider:)
        business_identifiers = business_security_header.to_s.split(",").map(&:strip).reject(&:empty?)
        # unsatisfied when header is empty
        return :no if business_identifiers.empty?

        if FeatureFlag.vexi.enabled?(:add_enterprise_access_verification_header_logging, default: false)
          GitHub.logger.info(
            "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
            "code.function": "multiple_businesses_satisfied?",
            "gh.enterprise_access_verification.header_value": business_security_header,
            "message": "Enterprise access verification header values"
          )
        end

        # unsatisfied when header contains more than 20 business identifiers
        return :no if business_identifiers.length > MAX_BUSINESSES_IN_HEADER

        businesses_from_header = businesses_from_security_header(business_identifiers)
        # unsatisfied when all business identifiers are invalid
        return :no if businesses_from_header.empty?

        if FeatureFlag.vexi.enabled?(:add_enterprise_access_verification_header_logging, default: false)
          GitHub.logger.info(
            "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
            "code.function": "multiple_businesses_satisfied?",
            "gh.enterprise_access_verification.header_value": business_security_header,
            "message": "Enterprise access verification businesses found from header"
          )
        end

        return :yes if anonymous_request?

        applicable_businesses = businesses_from_header.select { |business| business.enterprise_managed? && business.proxy_security_header_enabled? }
        current_actor = nil

        with_database_error_fallback(fallback: :no) do
          current_actor = actor || authenticated_key

          if FeatureFlag.vexi.enabled?(:add_enterprise_access_verification_header_logging, default: false)
            GitHub.logger.info(
              "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
              "code.function": "multiple_businesses_satisfied?",
              "gh.enterprise_access_verification.actor_id": current_actor&.id,
              "message": "Enterprise access verification current actor id"
            )
          end

          return :yes if applicable_businesses.include?(business_for(current_actor))
        end

        if FeatureFlag.vexi.enabled?(:add_enterprise_access_verification_header_logging, default: false)
          GitHub.logger.info(
            "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
            "code.function": "multiple_businesses_satisfied?",
            "gh.enterprise_access_verification.actor_id": current_actor&.id,
            "message": "Enterprise access verification current actor id not in applicable businesses"
          )
        end

        instrument_multiple_proxy_security_header_unsatisfied(applicable_businesses, current_actor)

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

      def legacy_slug_lookup_allowed?(slug)
        return false if slug.to_s.include?(",")
        LEGACY_ENTERPRISE_SLUGS.include?(slug.to_s.downcase.strip)
      end

      # Returns an array of Business objects from a comma-separated list of business slugs or IDs
      def businesses_from_security_header(businesses_in_header)
        return [] if businesses_in_header.empty?
        return @businesses if defined?(@businesses)

        # For multiple header values, ensure all are integers
        if businesses_in_header.length > 1
          if businesses_in_header.any? { |value| !integer?(value) }
            GitHub.logger.info(
              "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
              "code.function": "businesses_from_security_header",
              "gh.enterprise_access_verification.header_value": businesses_in_header.join(", "),
              "message": "Enterprise access verification rejected non-integer header value"
            )
            # Return empty array if any non-integer value is found
            return []
          end
        end

        @businesses = businesses_in_header.map do |value|
          if integer?(value)
            Business.find_by(id: value.to_i)
          else
            is_allowed = legacy_slug_lookup_allowed?(value)
            # Restrict non-legacy slug lookups when restriction feature flag is also enabled
            unless is_allowed
              instrument_legacy_slug_restriction(value)
              next nil
            end
            Business.find_by(slug: value)
          end
        end.compact
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

      def instrument_multiple_proxy_security_header_unsatisfied(businesses, current_actor)
        businesses.each do |business|
          instrument_proxy_security_header_unsatisfied(business, current_actor)
        end
      end

      def instrument_legacy_slug_restriction(header_value)
        GitHub.logger.info(
          "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
          "code.function": "legacy_slug_restriction",
          "gh.enterprise_access_verification.restricted_header_value": header_value,
          "message": "Enterprise access verification restricted legacy slug lookup"
        )
      end
    end
  end
end
