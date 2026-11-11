# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Concerns
      # Provides resilience for database cluster failures in Platform loaders.
      #
      # When included, loaders can gracefully degrade when specific database clusters
      # are unavailable, returning empty results instead of raising errors.
      #
      # Resilience is opt-in per request via GitHub.context[:resilient_clusters].
      # Set this in controllers that need graceful degradation:
      #
      # @example
      #   around_action :with_collab_cluster_resilience
      #
      #   def with_collab_cluster_resilience
      #     GitHub.context.push(resilient_clusters: ["collab"]) { yield }
      #   end
      module ClusterResilience
        extend T::Helpers
        extend ActiveSupport::Concern
        include GitHub::ResilienceMixin

        private

        sig { params(model_class: T.untyped).returns(T::Boolean) }
        def model_on_resilient_cluster?(model_class)
          clusters = GitHub.context[:resilient_clusters]
          return false unless clusters.is_a?(Array) && clusters.any?
          return false unless model_class.respond_to?(:connection_db_config)

          db_name = model_class.connection_db_config.name
          clusters.any? { |prefix| db_name.start_with?(prefix) }
        rescue StandardError
          false
        end

        sig { params(model: T.untyped).returns(T.untyped) }
        def extract_model_class(model)
          model.is_a?(::ActiveRecord::Relation) ? model.klass : model
        end
      end
    end
  end
end
