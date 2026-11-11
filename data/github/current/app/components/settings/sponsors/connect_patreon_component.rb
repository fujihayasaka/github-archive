# typed: strict
# frozen_string_literal: true

module Settings
  module Sponsors
    class ConnectPatreonComponent < ApplicationComponent
      # sponsor - User or Organization connecting to Patreon
      sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
      def initialize(sponsor:)
        @sponsor = sponsor
      end

      private

      sig { returns(GitHubSponsors::Types::Sponsor) }
      attr_reader :sponsor

      delegate :sponsors_patreon_user, to: :sponsor

      sig { returns(T::Boolean) }
      def render?
        return false unless GitHub.sponsors_enabled?
        return false if sponsors_patreon_user.present?

        sponsor.adminable_by?(current_user)
      end
    end
  end
end
