# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Mysql1 < Base
    primary_abstract_class

    connects_to_mysql1

    def self.production_schema_name
      "github_production"
    end

    def self.dedicated_background_destroy_queue_name
      "background_destroy_#{cluster_name.to_s.underscore}".to_sym
    end
  end
end
