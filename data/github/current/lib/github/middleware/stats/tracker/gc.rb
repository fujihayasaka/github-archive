# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Gc
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
            gc_info = GitHub::DataCollector::GCStatsCollector.get_instance
            return unless gc_info.enabled?

            tags = tags_cache.method_controller_action_service.dup
            tags << if gc_info.major_count > 0
              "gc:major"
            elsif gc_info.minor_count > 0
              "gc:minor"
            else
              "gc:none"
            end

            dogstats.distribution "request.dist.gc.allocations", gc_info.allocations, tags: tags
            dogstats.distribution "request.dist.old_object_increase", gc_info.old_object_increase, tags: tags
            dogstats.distribution "request.dist.gc.time", gc_info.time * 1000, tags: tags

            return unless gc_info.major_count > 0

            major_by = GC.latest_gc_info(:major_by)
            tags = tags_cache.method_controller_action_service.dup
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::MAJOR_BY_TAG, major_by)
            dogstats.distribution("ruby.gc.major_by", 1, tags: tags)
          end
        end
      end
    end
  end
end
