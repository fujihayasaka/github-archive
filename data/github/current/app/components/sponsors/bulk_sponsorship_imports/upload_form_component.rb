# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    class UploadFormComponent < ApplicationComponent
      extend T::Sig

      sig do
        params(
          sponsor: GitHubSponsors::Types::Sponsor,
          redirect_params: Sponsors::BulkSponsorshipImportsController::RedirectParams,
        ).void
      end
      def initialize(sponsor:, redirect_params:)
        @sponsor = sponsor
        @redirect_params = redirect_params
      end

      private

      sig { returns(GitHubSponsors::Types::Sponsor) }
      attr_reader :sponsor

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      attr_reader :redirect_params

      sig { returns(T::Boolean) }
      def can_import?
        !has_commercial_interaction_restriction? && !sponsors_invoicing_required_to_sponsor?
      end

      sig { returns(T::Boolean) }
      memoize def has_commercial_interaction_restriction?
        sponsor.has_commercial_interaction_restriction?
      end

      sig { returns(T::Boolean) }
      memoize def sponsors_invoicing_required_to_sponsor?
        sponsor.sponsors_invoicing_required_to_sponsor?
      end
    end
  end
end
