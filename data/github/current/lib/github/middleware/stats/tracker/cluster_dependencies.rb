# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class ClusterDependencies
          extend T::Sig
          extend Tracker

          sig do
            override.params(
              dogstats: T.untyped,
              env: T.untyped,
              stats: T::Hash[Symbol, T.untyped],
              tags_cache: GitHub::DatadogTagsCache,
            ).void
          end
          def self.track(dogstats, env, stats, tags_cache)
            controller_instance = env["action_controller.instance"]
            if controller_instance.present? && controller_instance.respond_to?(:required_clusters)
              required_clusters = Array(controller_instance.required_clusters).map(&:name)
              optional_clusters = Array(controller_instance.optional_clusters).map(&:name)
              emit_sampled_metric = defined?(GitHub.flipper) && GitHub.flipper[:request_cluster_queries_sampled_metric].enabled?

              GitHub::MysqlInstrumenter.queries_per_database.each do |cluster, count|
                tags = tags_cache.method_controller_action_service.dup

                tags << case cluster
                when *required_clusters
                  "status:required"
                when *optional_clusters
                  "status:optional"
                else
                  "status:undeclared"
                end

                cluster = GitHub::MysqlInstrumenter.cluster_names[cluster] || TaggingHelper::UNKNOWN
                TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::CLUSTER_TAG, cluster)

                dogstats.count("request.cluster.queries", count, tags: tags)
                dogstats.count("request.cluster.queries.sampled", count, tags: tags) if emit_sampled_metric
              end
            end
          end
        end
      end
    end
  end
end
