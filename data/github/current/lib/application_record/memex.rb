# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Memex < Base
    self.abstract_class = true

    def self.throttler_cluster_name
      :blanket
    end

    def self.production_schema_name
      "memex"
    end

    connects_to database: { writing: :memex_primary, reading: :memex_readonly }
  end
end
