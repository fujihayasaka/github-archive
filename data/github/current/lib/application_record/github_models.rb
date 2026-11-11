# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class GitHubModels < Base
    self.abstract_class = true

    connects_to database: { writing: :github_models_primary, reading: :github_models_readonly }

    def self.production_schema_name
      "github_models"
    end

    def self.throttler_cluster_name
      Ballast.throttler_cluster_name
    end
  end
end
