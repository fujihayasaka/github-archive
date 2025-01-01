# frozen_string_literal: true

module Campaigns
  class IndexComponent < ApplicationComponent
    include HasPagination
    attr_reader :sort, :status

    def initialize(sort:, status:, page:)
      @sort = sort || "desc"
      @status = status || "active"
      @page = normalize_page(page)
    end

    def campaigns
      return @campaigns if defined? @campaigns

      @campaigns = Campaign
        .by_status(@status)
        .order(created_at: @sort)
        .page(@page)
    end
  end
end
