# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Repositories < Base
    self.abstract_class = true

    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
       rand(100) < GitHub.environment.fetch("REPOSITORIES_CLUSTER_USE_VITESS_PERCENTAGE", 0).to_i

      connects_to database: {
        writing: :repositories_primary_vitess,
        reading: :repositories_readonly_vitess,
        reading_slow: :repositories_readonly_slow_vitess
      }
    else
      connects_to database: {
        writing: :repositories_primary,
        reading: :repositories_readonly,
        reading_slow: :repositories_readonly_slow
      }
    end

    def self.production_schema_name
      "github_production"
    end

    def self.dedicated_background_destroy_queue_name
      "background_destroy_#{cluster_name.to_s.underscore}".to_sym
    end

    if rand(100) < GitHub.environment.fetch("SKIP_REPOS_GTID_CHECK_PERCENTAGE", 0).to_i
      def self.skip_gtid_check?
        true
      end
    end

    if rand(100) < GitHub.environment.fetch("SKIP_REPOS_GTID_TRACK_PERCENTAGE", 0).to_i
      def self.gtid_tracking_enabled?
        false
      end
    end
  end
end
