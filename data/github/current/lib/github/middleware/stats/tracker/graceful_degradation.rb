# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class GracefulDegradation
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
            return unless defined?(GitHub::GracefulDegradationInstrumenter)

            handled_exceptions_count = GitHub::GracefulDegradationInstrumenter.handled_exceptions.count
            unhandled_exception = GitHub::GracefulDegradationInstrumenter.unhandled_exception

            # Report metrics only if there are any handled exceptions or an unhandled exception
            return if handled_exceptions_count.zero? && unhandled_exception.nil?

            tags = tags_cache.controller_action_service_method_status_category.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::HAS_HANDLED_EXCEPTIONS_TAG, handled_exceptions_count.positive?)

            if !unhandled_exception.nil?
              TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::UNHANDLED_EXCEPTION_CLASS_TAG, unhandled_exception.class.name)

              if unhandled_exception.respond_to?(:connection_pool) &&
                pool = unhandled_exception.connection_pool

                TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::UNHANDLED_EXCEPTION_DATABASE_CLUSTER_TAG, pool.connection_class&.name.split("::").last || TaggingHelper::UNKNOWN)
                TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::UNHANDLED_EXCEPTION_DATABASE_CONNECTION_ROLE_TAG, pool.role&.to_s || TaggingHelper::UNKNOWN)

                exception_cluster_status = TaggingHelper::UNKNOWN
                controller_instance = env["action_controller.instance"]

                if controller_instance.respond_to?(:required_clusters) &&
                  controller_instance.respond_to?(:optional_clusters) &&
                  cluster_name = pool.connection_class&.name

                  required_cluster_names = Array(controller_instance.required_clusters).map(&:name)
                  optional_cluster_names = Array(controller_instance.optional_clusters).map(&:name)

                  exception_cluster_status = case cluster_name
                  when *required_cluster_names
                    "required"
                  when *optional_cluster_names
                    "optional"
                  else
                    "undeclared"
                  end
                end

                TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::UNHANDLED_EXCEPTION_DATABASE_CLUSTER_STATUS_TAG, exception_cluster_status)
              end
            end

            time_budget_error_handled = GitHub::GracefulDegradationInstrumenter.handled_exceptions.any? { |e| e.is_a?(GitHub::RequestDurationManager::TimeBudgetIsOverError) }
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::EXHAUSTED_TIME_BUDGET_TAG, time_budget_error_handled)

            dogstats.distribution("request.resilience.dist.graceful_degradation", handled_exceptions_count, tags: tags)
          end
        end
      end
    end
  end
end
