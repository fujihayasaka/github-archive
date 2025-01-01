# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Migrations < Base
    self.abstract_class = true
    connects_to database: { writing: :migrations_primary, reading: :migrations_readonly }

    # Fix the use of the actual cluster name over the use of the class name.
    # this causes some errors on several places such as freno
    # that needs to know the cluster name for the throttler.
    def self.cluster_name
      :octoshift
    end
  end
end
