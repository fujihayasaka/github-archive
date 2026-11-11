# frozen_string_literal: true

module CVEs
  class IndexComponent < ApplicationComponent
    include HasPagination

    attr_reader :cves, :year

    def initialize(cves:, year:)
      @cves = cves
      @year = year
    end

    def year_options
      CVE.distinct.order(year: :DESC).pluck(:year)
    end
  end
end
