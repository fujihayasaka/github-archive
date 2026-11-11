# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Profiles < Base
    self.abstract_class = true

    connects_to database: { writing: :profiles_primary, reading: :profiles_readonly }

    def self.production_schema_name
      "profiles"
    end

    # Fix: Use the actual cluster name instead of using the class name.
    # This causes some errors on several places such as Freno
    # that needs to know the cluster name for the throttler.
    def self.cluster_name
      :munger
    end

    def self.throttler_cluster_name
      :munger
    end
  end
end
