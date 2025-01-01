# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SecurityAdvisoryOrderField < Platform::Enums::Base
      visibility :public

      description "Properties by which security advisory connections can be ordered."

      value "PUBLISHED_AT", "Order advisories by publication time", value: "published_at"
      value "UPDATED_AT", "Order advisories by update time", value: "updated_at"
      value "EPSS_PERCENTAGE", "Order advisories by EPSS percentage", value: "epss_percentage"
      value "EPSS_PERCENTILE", "Order advisories by EPSS percentile", value: "epss_percentile"
    end
  end
end
