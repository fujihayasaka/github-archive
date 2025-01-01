# typed: true
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class SponsorshipComponent < ApplicationComponent
        # sponsorship - a Sponsorship
        # sponsor - an Organization
        # is_even_row - optional Boolean indicating if this is an evenly numbered row in the table of all transfers
        def initialize(sponsorship:, sponsor:, is_even_row: false)
          @sponsorship = sponsorship
          @sponsor = sponsor
          @is_even_row = !!is_even_row
        end

        private

        attr_reader :sponsorship, :sponsor

        def render?
          sponsorship.present? && sponsor.present? && sponsorship.sponsor_id == sponsor.id && logged_in? &&
            GitHub.sponsors_enabled?
        end

        def even_row?
          @is_even_row
        end

        def column_classes
          bg_class = if even_row?
            "color-bg-default"
          else
            "color-bg-inset"
          end
          helpers.class_names("px-2", "no-wrap", bg_class)
        end

        def expires?
          sponsorship.active? && sponsorship.expires_at.present?
        end
      end
    end
  end
end
