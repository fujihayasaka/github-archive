# typed: true
# frozen_string_literal: true

module Billing
  class DownloadReportComponent < ApplicationComponent
    attr_reader :tooltip, :attrs
    def initialize(tooltip: nil, **attrs)
      @tooltip = tooltip
      @attrs = attrs
    end
  end
end
