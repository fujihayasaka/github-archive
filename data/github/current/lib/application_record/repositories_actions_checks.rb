# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class RepositoriesActionsChecks < Base
    self.abstract_class = true

    def self.cluster_name
      :"repositories-actions-checks"
    end

    connects_to database: { writing: :repositories_actions_checks_primary, reading: :repositories_actions_checks_readonly }
  end
end
