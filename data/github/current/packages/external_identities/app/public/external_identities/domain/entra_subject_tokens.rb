# typed: strict
# frozen_string_literal: true

require "oidc"

module ExternalIdentities
  class Domain
    class EntraSubjectTokens < GH::Domain::Base
      INVALID_JWT_DESCRIPTION = T.let("subject_token is not a valid JWT", String)
      UNSUPPORTED_AUDIENCE_DESCRIPTION = T.let("subject_token audience is not supported", String)
      UNKNOWN_TENANT_DESCRIPTION = T.let("subject_token tenant is not recognized", String)
      VERIFICATION_FAILED_DESCRIPTION = T.let("subject_token verification failed", String)

      class VerifiedSubjectToken < T::Struct
        const :claims, T::Hash[T.untyped, T.untyped]
        const :headers, T::Hash[T.untyped, T.untyped]
        const :business_id, Integer
      end

      REQUIRED_SUBJECT_TOKEN_CLAIMS = T.let(%w[iss tid oid aud].freeze, T::Array[String])
      SAML_AUDIENCE_PATH_REGEX = T.let(%r{\A#{Regexp.escape(GitHub.url)}/(enterprises|orgs)/}, Regexp)

      # Public: Verifies an Entra subject token.
      #
      # subject_token - The String subject token.
      #
      # Returns a GH::Result containing the verified token claims, headers, and business ID.
      sig { params(subject_token: String).returns(GH::Result[VerifiedSubjectToken]).checked(:always).on_failure(:raise) }
      def verify_subject_token(subject_token:)
        ActiveRecord::Base.connected_to(role: :reading) do
          parse_result = OIDC::TokenValidator.parse_token(subject_token)
          unless parse_result.success?
            return error(INVALID_JWT_DESCRIPTION)
          end

          unverified_claims = parse_result.claims
          failure = unverified_claim_failure(unverified_claims)
          return failure unless failure.nil?

          verify_for_tenant(subject_token, unverified_claims)
        end
      end

      private

      sig { params(unverified_claims: T.untyped).returns(T.nilable(GH::Result::Error[T.untyped])) }
      def unverified_claim_failure(unverified_claims)
        missing_claims_failure(unverified_claims) ||
          unsupported_audience_failure(unverified_claims)
      end

      sig { params(unverified_claims: T.untyped).returns(T.nilable(GH::Result::Error[T.untyped])) }
      def missing_claims_failure(unverified_claims)
        missing_claims = REQUIRED_SUBJECT_TOKEN_CLAIMS.reject { |claim| unverified_claims.key?(claim) }

        if missing_claims.any?
          return error("subject_token is missing required claims: #{missing_claims.join(',')}")
        end

        nil
      end

      sig { params(unverified_claims: T.untyped).returns(T.nilable(GH::Result::Error[T.untyped])) }
      def unsupported_audience_failure(unverified_claims)
        audiences = Array.wrap(unverified_claims["aud"])
        if audiences.any? { |audience| audience.to_s.match?(SAML_AUDIENCE_PATH_REGEX) }
          return error(UNSUPPORTED_AUDIENCE_DESCRIPTION)
        end

        nil
      end

      sig { params(subject_token: String, unverified_claims: T.untyped).returns(GH::Result[VerifiedSubjectToken]) }
      def verify_for_tenant(subject_token, unverified_claims)
        business = business_for_tenant(unverified_claims["tid"].to_s)
        if business.nil?
          return error(UNKNOWN_TENANT_DESCRIPTION)
        end

        verify_for_business(subject_token, business)
      end

      sig { params(subject_token: String, business: Business).returns(GH::Result[VerifiedSubjectToken]) }
      def verify_for_business(subject_token, business)
        verification_result = OIDC::TokenValidator.validate_token(subject_token, OIDC::TenantProvider.new(business))
        unless verification_result.success?
          return error(VERIFICATION_FAILED_DESCRIPTION)
        end

        verified_subject_token_result(verification_result, business)
      end

      sig { params(verification_result: T.untyped, business: Business).returns(GH::Result[VerifiedSubjectToken]) }
      def verified_subject_token_result(verification_result, business)
        GH::Result::Ok.new(VerifiedSubjectToken.new(
          claims: verification_result.claims,
          headers: verification_result.headers,
          business_id: business.id
        ))
      end

      sig { params(tenant_id: String).returns(T.nilable(Business)) }
      def business_for_tenant(tenant_id)
        Business::OIDCProvider.find_by(tenant_id:, oidc_provider: "azure")&.business
      end

      sig { params(description: String).returns(GH::Result::Error[T.untyped]) }
      def error(description)
        GH::Result::Error.new(description)
      end
    end
  end
end
