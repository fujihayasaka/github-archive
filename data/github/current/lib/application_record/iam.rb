# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Iam < Base
    self.abstract_class = true

    def self.throttler_cluster_name
      Collab.throttler_cluster_name
    end

    def self.production_schema_name
      "iam_production"
    end

    connects_to database: { writing: :iam_primary, reading: :iam_readonly }
  end
end
