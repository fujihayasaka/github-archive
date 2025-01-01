# typed: true
# frozen_string_literal: true

module Search
  module Chatops
    class MemexProjectItemsRepairIndex < RepairIndex
      extend T::Sig

      include ActionView::Helpers::NumberHelper

      sig { params(count: Integer, visited_after: T.nilable(String)).returns(String) }
      def start(count = 1, visited_after = nil)
        repair_job.enable

        if visited_after.present?
          begin
            repair_job.visited_after = Date.iso8601(visited_after)
          rescue ArgumentError
            return "Invalid --visited-after date format, expected YYYY-MM-DD"
          end
        end

        repair_job.start(count)

        GitHub.dogstats.event \
          "Repair started for: #{index_name.inspect}",
          "Repair has been started for #{index_name.inspect} with #{count} workers using search chatops",
          tags: %W[search:ops action:repair-start from:chatops]

        if repair_job.visited_after?
          "Repair has been started for #{index_name.inspect} for projects visited after #{repair_job.visited_after} with #{count} #{"worker".pluralize(count)}"
        else
          "Repair has been started for #{index_name.inspect} for all projects with #{count} #{"worker".pluralize(count)}"
        end
      end

      sig { returns(String) }
      def status
        if repair_job.active?
          time = repair_job.estimated_completion_time
          time = time.nil? ? "no estimated completion time" : time.strftime("%Y-%m-%d %H:%M:%S %Z")
          "#{index_name} #{progress_bar} (#{time})\n\n#{processed_records}"

        elsif repair_job.paused?
          "#{index_name} #{progress_bar} (paused)\n\n#{processed_records}"

        elsif repair_job.finished?
          stats = repair_job.stats
          finished = stats[:finished].strftime("%Y-%m-%d %H:%M:%S %Z")
          "#{index_name} finished at #{finished}\n\n#{processed_records(stats)}"

        else
          "No repair running for #{index_name.inspect}"
        end
      end

      sig { returns(RepairMemexProjectItemsIndexJob) }
      def repair_job
        return @repair_job if defined? @repair_job

        @repair_job = RepairMemexProjectItemsIndexJob.new(index_name)
        unless @repair_job.index.exists?
          raise ArgumentError, "Unknown index: #{index_name.inspect}"
        end
        @repair_job
      end

      private

      # Returns a String describing the number of records processed thus far
      sig { params(stats: T.nilable(T::Hash[Symbol, T.untyped])).returns(String) }
      def processed_records(stats = repair_job.stats)
        reconciler = repair_job.reconciler
        started = stats[:started]
        finished = repair_job.finished? ? stats[:finished] : Time.now
        elapsed = distance_of_time_in_words(started, finished, include_seconds: true)

        prefix = if repair_job.visited_after?
          reconciler = T.cast(reconciler, MemexProject::VisitedAfterReconciler)

          <<~MSG
            Repair strategy: Visited after
            Visited after: #{repair_job.visited_after}
            Batch offset: #{reconciler.last_visited_on}
          MSG
        else
          "Repair strategy: All projects"
        end

        msg = <<~MSG
          #{prefix}
          Elapsed: #{elapsed}

          Number of MemexProject records reconciled: #{number_with_delimiter(reconciler.memex_projects_reconciled_count)}
          Number of MemexProjectItem records read: #{number_with_delimiter(stats[:total])}

          memex-project-items documents added: #{number_with_delimiter(stats[:added])}
          memex-project-items documents updated: #{number_with_delimiter(stats[:updated])}
          memex-project-items documents removed: #{number_with_delimiter(stats[:removed])}

          Active MemexProject reconciler batches: #{number_with_delimiter(reconciler.reconciler_batches_count)}
          Failed MemexProject reconciler batches: #{number_with_delimiter(reconciler.failed_reconciler_batches_count)}
          MemexProject records that could not be reconciled: #{number_with_delimiter(stats[:error])}
        MSG
      end
    end
  end
end
