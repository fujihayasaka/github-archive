# typed: strict
# frozen_string_literal: true

module Settings
  module Sponsors
    class DisconnectPatreonComponent < ApplicationComponent
      # sponsor - User or Organization disconnecting Patreon
      sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      private

      sig { returns(GitHubSponsors::Types::Sponsor) }
      attr_reader :sponsor

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.sponsors_enabled? && sponsor.sponsors_patreon_user.present?
        sponsor.adminable_by?(current_user)
      end

      sig { returns(SponsorsPatreonUser) }
      memoize def sponsors_patreon_user
        T.must_because(sponsor.sponsors_patreon_user) do
          "component does not render unless a SponsorsPatreonUser is present"
        end
      end

      sig { returns(String) }
      def patreon_email
        sponsors_patreon_user.patreon_email
      end
    end
  end
end
