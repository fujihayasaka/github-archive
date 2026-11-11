# frozen_string_literal: true

module Campaigns
  class TableComponent < ApplicationComponent
    include HasSorting
    attr_reader :campaigns, :sort

    def initialize(campaigns:, sort: nil)
      @campaigns = campaigns
      @sort = sort
    end
  end
end
