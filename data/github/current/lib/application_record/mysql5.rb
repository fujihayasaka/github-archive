# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Mysql5 < Base
    self.abstract_class = true

    connects_to database: { writing: :kv_primary, reading: :kv_readonly }

    def self.production_schema_name
      "github_production"
    end
  end
end
