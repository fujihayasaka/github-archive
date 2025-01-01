# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class SponsorshipsListComponent < ApplicationComponent
        # sponsorships - a WillPaginate::Collection of Sponsorship records
        # sponsor - the Organization funding the sponsorships
        def initialize(sponsorships:, sponsor:)
          @sponsorships = sponsorships
          @sponsor = sponsor
        end

        private

        attr_reader :sponsor, :sponsorships

        def render?
          sponsor.present? && logged_in? && GitHub.sponsors_enabled?
        end
      end
    end
  end
end
