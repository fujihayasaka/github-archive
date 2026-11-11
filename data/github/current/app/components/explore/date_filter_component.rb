# typed: true
# frozen_string_literal: true

module Explore
  class DateFilterComponent < ApplicationComponent
    include ExploreHelper

    def initialize(since:)
      @since = fetch_or_fallback(DATE_OPTIONS.keys, since, "weekly")
    end
  end
end
