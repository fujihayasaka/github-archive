# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain

    if Rails.env.test? || Rails.env.development? || (Rails.env.production? && rand(100) < GitHub.environment.fetch("PAGES_TABLES_USE_NEW_CLUSTER_PERCENTAGE", 0).to_i) # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      require_relative "./pages_from_repositories_pages"
    else
      require_relative "./pages_from_repositories_repositories"
    end

    class PagesFromRepositories
      self.abstract_class = true
    end
  end
end
