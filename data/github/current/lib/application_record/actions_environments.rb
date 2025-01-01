# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class ActionsEnvironments < Base
    self.abstract_class = true

    def self.cluster_name
      :"actions-environments"
    end

    connects_to database: { writing: :actions_environments_primary, reading: :actions_environments_readonly }
  end
end
