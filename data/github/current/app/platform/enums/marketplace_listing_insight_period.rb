# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingInsightPeriod < Platform::Enums::Base
      description "The possible time periods for which Marketplace listing insights can be requested."
      visibility :internal

      value "DAY", "The previous calendar day", value: :day
      value "WEEK", "The previous seven days", value: :week
      value "MONTH", "The previous thirty days", value: :month
      value "ALLTIME", "Since the listing was approved", value: :alltime
    end
  end
end
