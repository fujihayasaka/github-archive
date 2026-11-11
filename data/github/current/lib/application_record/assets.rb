# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Assets < Base
    self.abstract_class = true

    connects_to database: { writing: :assets_primary, reading: :assets_readonly }

    def self.production_schema_name
      "github_production"
    end
  end
end
