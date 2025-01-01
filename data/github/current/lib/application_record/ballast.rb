# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Ballast < Base
    self.abstract_class = true

    connects_to database: { writing: :ballast_primary, reading: :ballast_readonly }

    def self.production_schema_name
      "github_production"
    end
  end
end
