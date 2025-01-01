# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Pages < Base
    self.abstract_class = true

    connects_to database: { writing: :pages_primary, reading: :pages_readonly }

    def self.production_schema_name
      "pages"
    end
  end
end
