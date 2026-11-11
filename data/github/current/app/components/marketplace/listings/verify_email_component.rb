# typed: strict
# frozen_string_literal: true

module Marketplace
  module Listings
    class VerifyEmailComponent < ApplicationComponent
      sig { returns(::Organization) }
      attr_reader :organization

      sig do
        params(
          organization: ::Organization,
        ).void
      end
      def initialize(organization:)
        @organization = organization
      end

      sig { returns(T.nilable(::OrganizationProfileEmail)) }
      memoize def profile_email_verification
        organization.profile_email_verification
      end

      sig { returns(T.nilable(T::Boolean)) }
      def email_verification_pending?
        profile_email_verification&.unverified?
      end

      sig { returns(T.nilable(T::Boolean)) }
      def email_verified?
        profile_email_verification.present? && profile_email_verification&.verified?
      end

      sig { returns(String) }
      def set_public_email_path
        settings_org_profile_path(organization)
      end

      sig { returns(String) }
      def verify_email_path
        profile_emails_path(organization)
      end

      sig { returns(String) }
      def resend_verification_path
        resend_verification_request_profile_email_path(organization, profile_email_verification)
      end
    end
  end
end
