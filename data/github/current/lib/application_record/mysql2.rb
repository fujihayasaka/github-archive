# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Mysql2 < Base
    self.abstract_class = true

    connects_to database: { writing: :notifications_primary, reading: :notifications_readonly }

    def self.production_schema_name
      "github_production"
    end
  end
end
