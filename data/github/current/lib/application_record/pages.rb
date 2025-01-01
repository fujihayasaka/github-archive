# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Pages < Base
    self.abstract_class = true

    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      rand(100) < GitHub.environment.fetch("PAGES_CLUSTER_USE_REPOS_VTGATES_PERCENTAGE", 0).to_i
      connects_to database: { writing: :pages_primary_repos_vtgates, reading: :pages_readonly_repos_vtgates }
    else
      connects_to database: { writing: :pages_primary, reading: :pages_readonly }
    end

    sig { returns(T::Array[Symbol]) }
    def self.throttler_cluster_names
      if GitHub.flipper[:throttle_pages_on_both_clusters].enabled?
        super + [ApplicationRecord::Repositories.cluster_name]
      else
        super
      end
    end

    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      rand(100) < GitHub.environment.fetch("PAGES_CLUSTER_SUM_REPOS_REPLICATION_LAG_PERCENTAGE", 0).to_i

      def self.default_replication_wait!
        super + Freno.client.replication_delay(store_name: :"repositories") * 1000
      end

    end

    def self.production_schema_name
      "pages"
    end
  end
end
