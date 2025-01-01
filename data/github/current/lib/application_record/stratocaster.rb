# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Stratocaster < Base
    self.abstract_class = true

    connects_to database: { writing: :stratocaster_primary, reading: :stratocaster_readonly }

    def self.production_schema_name
      "stratocaster_production"
    end
  end
end
