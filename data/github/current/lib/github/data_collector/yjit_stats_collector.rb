# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class YJITStatsCollector < GitHub::DataCollector::Collector
      set_callback :reset, :after do |collector|
        stats = collector.stats

        collector.inline_code_size = stats.fetch(:inline_code_size)
        collector.outlined_code_size = stats.fetch(:outlined_code_size)
        collector.vm_insns_count = stats.fetch(:vm_insns_count, 0)
        collector.yjit_alloc_size = stats.fetch(:yjit_alloc_size)
        collector.compile_time_ns = stats.fetch(:compile_time_ns)

        if RubyVM::YJIT.stats_enabled?
          collector.yjit_insns_count = collector.yjit_insns_count_from_stats
          collector.side_exit_count = stats.fetch(:side_exit_count)
          collector.total_exit_count = stats.fetch(:total_exit_count)
          collector.ratio_in_yjit = stats.fetch(:ratio_in_yjit, 0.0)
          collector.avg_len_in_yjit = stats.fetch(:avg_len_in_yjit)
        end
      end

      def self.collector_name
        :yjit_stats_collector
      end

      attributes :inline_code_size,
        :outlined_code_size,
        :vm_insns_count,
        :yjit_alloc_size,
        :compile_time_ns,
        :yjit_insns_count,
        :side_exit_count,
        :total_exit_count,
        :ratio_in_yjit,
        :avg_len_in_yjit

      def stats
        T.must(RubyVM::YJIT.runtime_stats)
      end

      def inline_code_size_per_req
        stats.fetch(:inline_code_size) - inline_code_size
      end

      def outlined_code_size_per_req
        stats.fetch(:outlined_code_size) - outlined_code_size
      end

      def vm_insns_count_per_req
        stats.fetch(:vm_insns_count, 0) - vm_insns_count
      end

      def yjit_alloc_size_per_req
        stats.fetch(:yjit_alloc_size) - yjit_alloc_size
      end

      def compile_time_ns_per_req
        stats.fetch(:compile_time_ns) - compile_time_ns
      end

      def yjit_insns_count_per_req
        yjit_insns_count_from_stats - yjit_insns_count
      end

      def side_exit_count_per_req
        stats.fetch(:side_exit_count) - side_exit_count
      end

      def total_exit_count_per_req
        stats.fetch(:total_exit_count) - total_exit_count
      end

      def ratio_in_yjit_per_req
        total_insns_count_per_req = (retired_in_yjit_per_req + vm_insns_count_per_req).clamp(1, Float::INFINITY)
        100.0 * retired_in_yjit_per_req.to_f / total_insns_count_per_req
      end

      def avg_len_in_yjit_per_req
        retired_in_yjit_per_req.to_f / total_exit_count_per_req
      end

      def yjit_insns_count_from_stats
        # Ruby 3.2: exec_instruction
        # Ruby 3.3+: yjit_insns_count
        stats.fetch(:yjit_insns_count) { stats.fetch(:exec_instruction) }
      end

      private

      def retired_in_yjit_per_req
        yjit_insns_count_per_req - side_exit_count_per_req
      end
    end
  end
end
