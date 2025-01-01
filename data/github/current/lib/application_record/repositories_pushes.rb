# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class RepositoriesPushes < Base
    include GitHub::MaxExecutionTime

    self.abstract_class = true

    def self.cluster_name
      :"repositories-pushes-sharded"
    end

    def self.dedicated_background_destroy_queue_name
      :background_destroy_repositories_pushes
    end

    connects_to database: { writing: :repositories_pushes_sharded_primary, reading: :repositories_pushes_sharded_readonly }
  end
end
