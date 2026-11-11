# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class SecurityOverviewAnalytics < Base
    self.abstract_class = true

    connects_to database: { writing: :security_overview_analytics_primary, reading: :security_overview_analytics_readonly }

    def self.cluster_name
      :"security-overview"
    end

    def self.production_schema_name
      "security_overview_analytics"
    end

    def self.use_index(index_name)
      self.from("#{self.quoted_table_name} USE INDEX (#{index_name})")
    end
  end
end
