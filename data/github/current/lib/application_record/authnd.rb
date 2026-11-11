# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Authnd < Base
    self.abstract_class = true

    # Fix the use of the actual cluster name over the use of the class name.
    # this causes some errors on several places such as freno
    # that needs to know the cluster name for the throttler.
    def self.cluster_name
      :"authnd-production"
    end

    def self.throttler_cluster_name
      :"authnd-production"
    end

    connects_to database: { writing: :authnd_primary, reading: :authnd_readonly }
  end
end
