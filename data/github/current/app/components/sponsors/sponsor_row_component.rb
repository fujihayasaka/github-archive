# typed: true
# frozen_string_literal: true

module Sponsors
  class SponsorRowComponent < ApplicationComponent
    include AvatarHelper

    # sponsorship - a Sponsorship record
    # index - zero-based Integer index indicating where this row is relative to its siblings
    # current_page - Integer current page of results
    # per_page - Integer amount of rows being shown per page
    def initialize(sponsorship:, index:, current_page:, per_page:)
      @sponsorship = sponsorship
      @tier = sponsorship&.tier
      @index = index
      @current_page = current_page
      @per_page = per_page
    end

    def render?
      sponsorship.present?
    end

    private

    attr_reader :sponsorship, :index, :current_page, :per_page, :tier

    def row_number
      ((current_page - 1) * per_page) + index + 1
    end

    def sponsor
      sponsorship.linked_or_direct_sponsor
    end

    def item_monthly_price
      if sponsorship.manual_invoiced?
        sponsorship.amount
      else
        tier.base_price(duration: "month")
      end
    end

    def selected_at
      sponsorship.subscribable_selected_at || sponsorship.created_at
    end
  end
end
