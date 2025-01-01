# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Notify < Base
    self.abstract_class = true

    connects_to database: { writing: :notify_primary, reading: :notify_readonly }

    def self.production_schema_name
      "github_production"
    end

    def self.use_index(index_name)
      self.from("#{self.quoted_table_name} USE INDEX (#{index_name})")
    end
  end
end
