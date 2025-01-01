# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class Yjit
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
            return unless defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?

            tags = []
            TaggingHelper.add_tag_unless_nil(tags, TaggingHelper::STATS_MODE_TAG, RubyVM::YJIT.stats_enabled?)
            per_req_tags = tags + tags_cache.controller_action

            yjit_info = GitHub::DataCollector::YJITStatsCollector.get_instance

            dogstats.distribution("unicorn.yjit.inline_code_size", yjit_info.inline_code_size, tags: tags)
            dogstats.distribution("unicorn.yjit.inline_code_size_per_req", yjit_info.inline_code_size_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.outlined_code_size", yjit_info.outlined_code_size, tags: tags)
            dogstats.distribution("unicorn.yjit.outlined_code_size_per_req", yjit_info.outlined_code_size_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.vm_insns_count", yjit_info.vm_insns_count, tags: tags)
            dogstats.distribution("unicorn.yjit.vm_insns_count_per_req", yjit_info.vm_insns_count_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.yjit_alloc_size", yjit_info.yjit_alloc_size, tags: tags)
            dogstats.distribution("unicorn.yjit.yjit_alloc_size_per_req", yjit_info.yjit_alloc_size_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.compile_time_ns", yjit_info.compile_time_ns, tags: tags)
            dogstats.distribution("unicorn.yjit.compile_time_ns_per_req", yjit_info.compile_time_ns_per_req, tags: per_req_tags)

            return unless RubyVM::YJIT.stats_enabled?

            dogstats.distribution("unicorn.yjit.yjit_insns_count", yjit_info.yjit_insns_count, tags: tags)
            dogstats.distribution("unicorn.yjit.yjit_insns_count_per_req", yjit_info.yjit_insns_count_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.side_exit_count", yjit_info.side_exit_count, tags: tags)
            dogstats.distribution("unicorn.yjit.side_exit_count_per_req", yjit_info.side_exit_count_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.total_exit_count", yjit_info.total_exit_count, tags: tags)
            dogstats.distribution("unicorn.yjit.total_exit_count_per_req", yjit_info.total_exit_count_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.ratio_in_yjit", yjit_info.ratio_in_yjit, tags: tags)
            dogstats.distribution("unicorn.yjit.ratio_in_yjit_per_req", yjit_info.ratio_in_yjit_per_req, tags: per_req_tags)
            dogstats.distribution("unicorn.yjit.avg_len_in_yjit", yjit_info.avg_len_in_yjit, tags: tags)
            dogstats.distribution("unicorn.yjit.avg_len_in_yjit_per_req", yjit_info.avg_len_in_yjit_per_req, tags: per_req_tags)
          end
        end
      end
    end
  end
end
