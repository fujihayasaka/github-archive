# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Spokes < Base
    self.abstract_class = true

    connects_to database: { writing: :spokes_write, reading: :spokes_readonly, reading_slow: :spokes_readonly_slow }

    def self.production_schema_name
      "github_production"
    end
  end
end
