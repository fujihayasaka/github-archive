# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class ActionsEnvironments < Base
    self.abstract_class = true

    def self.cluster_name
      :"actions-environments"
    end

    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      rand(100) < GitHub.environment.fetch("ACTIONS_ENVIRONMENTS_GLB_CONNECTION_PERCENTAGE", 0).to_i
      connects_to database: { writing: :actions_environments_primary_non_vitess, reading: :actions_environments_readonly_non_vitess }
    else
      connects_to database: { writing: :actions_environments_primary, reading: :actions_environments_readonly }
    end

    if rand(100) < GitHub.environment.fetch("SKIP_ACTIONS_ENVIRONMENTS_GTID_TRACK_PERCENTAGE", 0).to_i
      def self.gtid_tracking_enabled?
        false
      end
    end
  end
end
