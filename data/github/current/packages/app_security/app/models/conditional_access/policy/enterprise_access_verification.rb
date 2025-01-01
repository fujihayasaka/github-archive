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

        if FeatureFlag.vexi.enabled?(:multiple_enterprise_access_verification, default: false)
          # call a method that determines if policy is applicable with multiple enterprise support in the header
          multiple_businesses_applicable?(business_security_header)
        else
          # skip to enforceable if business slug is not valid, will be handled by the policy enforcement
          business_from_header = business_from_security_header(business_security_header)
          return :yes unless business_from_header

          # not applicable for non-enterprise managed business
          return :no unless business_from_header.enterprise_managed?
          return :no unless business_from_header.proxy_security_header_enabled?

          :yes
        end
      end

      # Satisfied if the actor belongs to the same enterprise as the current business from the "sec-GitHub-allowed-enterprise" header
      def enterprise_access_verification_satisfied(resource:, target_provider:)
        if FeatureFlag.vexi.enabled?(:multiple_enterprise_access_verification, default: false)
          multiple_businesses_satisfied?(business_security_header)
        else
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

      def multiple_businesses_applicable?(header_value)
        business_identifiers = header_value.to_s.split(",").map(&:strip).reject(&:empty?)
        # applicable when header is empty, which will be blocked as part of satisfied check
        return :yes if business_identifiers.empty?

        # applicable when header contains more than 20 business identifiers, which will be blocked as part of satisfied check
        return :yes if business_identifiers.length > MAX_BUSINESSES_IN_HEADER

        businesses_from_header = businesses_from_security_header(business_identifiers)
        # applicable when header contains invalid business identifiers, which will be blocked as part of satisfied check
        return :yes if businesses_from_header.empty?

        # applicable when header contains multiple businesses but multiple businesses support is not enabled
        return :yes if header_value.to_s.include?(",") && businesses_from_header.none?(&:multiple_enterprise_access_verification_enabled?)

        # inapplicable when header does not contain a business that is enterprise managed
        return :no unless businesses_from_header.any?(&:enterprise_managed?)

        # inapplicable when header does not contain a business with proxy security enabled
        return :no unless businesses_from_header.any?(&:proxy_security_header_enabled?)

        # otherwise applicable
        :yes
      end

      def multiple_businesses_satisfied?(header_value)
        business_identifiers = header_value.to_s.split(",").map(&:strip).reject(&:empty?)
        # unsatisfied when header is empty
        return :no if business_identifiers.empty?

        # unsatisfied when header contains more than 20 business identifiers
        return :no if business_identifiers.length > MAX_BUSINESSES_IN_HEADER

        businesses_from_header = businesses_from_security_header(business_identifiers)
        # unsatisfied when all business identifiers are invalid
        return :no if businesses_from_header.empty?

        # unsatisfied when header contains multiple businesses but multiple businesses support is not enabled
        return :no if header_value.to_s.include?(",") && businesses_from_header.none?(&:multiple_enterprise_access_verification_enabled?)

        return :yes if anonymous_request?

        applicable_businesses = businesses_from_header.select { |business| business.enterprise_managed? && business.proxy_security_header_enabled? }
        current_actor = nil

        with_database_error_fallback(fallback: :no) do
          current_actor = actor || authenticated_key
          return :yes if applicable_businesses.include?(business_for(current_actor))
        end

        instrument_multiple_proxy_security_header_unsatisfied(applicable_businesses, current_actor)

        :no
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
            # Log legacy slug lookup if feature flag is enabled
            if FeatureFlag.vexi.enabled?(:enterprise_access_verification_legacy_slug_logging, default: false)
              is_allowed = legacy_slug_lookup_allowed?(value)
              instrument_legacy_slug_lookup(value, is_allowed)
              # Restrict non-legacy slug lookups when restriction feature flag is also enabled
              if FeatureFlag.vexi.enabled?(:enterprise_access_verification_legacy_slug_restriction, default: false)
                unless is_allowed
                  instrument_legacy_slug_restriction(value)
                  next nil
                end
              end
            end

            Business.find_by(slug: value)
          end
        end.compact
      end

      def business_from_security_header(header_value)
        return unless header_value
        return @business if defined?(@business)

        @business = if integer?(header_value)
          Business.find_by(id: header_value.to_i)
        else
          # Log legacy slug lookup if feature flag is enabled
          if FeatureFlag.vexi.enabled?(:enterprise_access_verification_legacy_slug_logging, default: false)
            is_allowed = legacy_slug_lookup_allowed?(header_value)
            instrument_legacy_slug_lookup(header_value, is_allowed)
          end

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

      def instrument_multiple_proxy_security_header_unsatisfied(businesses, current_actor)
        businesses.each do |business|
          instrument_proxy_security_header_unsatisfied(business, current_actor)
        end
      end

      def instrument_legacy_slug_lookup(header_value, is_allowed)
        GitHub.logger.info(
          "code.namespace": "ConditionalAccess::Policy::EnterpriseAccessVerification",
          "code.function": "legacy_slug_lookup",
          "gh.enterprise_access_verification.header_value": header_value,
          "gh.enterprise_access_verification.is_legacy_slug_lookup_allowed": is_allowed
        )
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
