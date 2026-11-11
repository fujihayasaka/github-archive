# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Collab < Base
    self.abstract_class = true

    connects_to database: { writing: :collab_primary, reading: :collab_readonly }

    def self.production_schema_name
      "github_production"
    end
  end
end
