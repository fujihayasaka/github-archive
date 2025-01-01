# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Repositories < Base
    self.abstract_class = true

    DOTCOM_KUBE_CLUSTER_NAMES = %w[
      dotcom-1-ash1-iad
      dotcom-2-ash1-iad
      dotcom-3-ash1-iad
      dotcom-7-ac4-iad
      dotcom-7-va3-iad
      dotcom-8-ac4-iad
      dotcom-8-va3-iad
      dotcom-9-ac4-iad
      dotcom-9-va3-iad
    ].freeze

    ISTIO_ENABLED_UNICORN_DEPLOYMENTS = %w[
      unicorn-api
      unicorn-api-graphql
    ].freeze

    if Rails.env.production? && # rubocop:disable GitHub/DoNotBranchOnRailsEnv
       rand(100) < GitHub.environment.fetch("REPOSITORIES_CLUSTER_USE_VITESS_PERCENTAGE", 0).to_i

      if ENV["LUC_PERFORMANCE"] == "1" || GitHub.review_lab? ||
        (
          rand(100) < GitHub.environment.fetch("REPOSITORIES_CLUSTER_USE_VITESS_DOTCOM_CLUSTER_PERCENTAGE", 0).to_i &&
          GitHub.kube? &&
          ISTIO_ENABLED_UNICORN_DEPLOYMENTS.include?(ENV.fetch("KUBE_DEPLOYMENT_NAME", "")) &&
          DOTCOM_KUBE_CLUSTER_NAMES.include?(GitHub.kubernetes_cluster_name)
        )
        connects_to database: {
          writing: :repositories_primary_vitess_dotcom_cluster,
          reading: :repositories_readonly_vitess_dotcom_cluster,
          reading_slow: :repositories_readonly_slow_vitess_dotcom_cluster
        }
      else
        connects_to database: {
          writing: :repositories_primary_vitess,
          reading: :repositories_readonly_vitess,
          reading_slow: :repositories_readonly_slow_vitess
        }
      end
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
