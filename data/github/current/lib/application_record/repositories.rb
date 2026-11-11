# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Repositories < Base
    self.abstract_class = true

    connects_to database: {
      writing: :repositories_primary,
      reading: :repositories_readonly,
      reading_slow: :repositories_readonly_slow
    }

    def self.production_schema_name
      "github_production"
    end

    def self.dedicated_background_destroy_queue_name
      "background_destroy_#{cluster_name.to_s.underscore}".to_sym
    end
  end
end
