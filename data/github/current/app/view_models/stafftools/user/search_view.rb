# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class SearchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      DEFAULT_BACKFILL_WORKERS = 1
      MAX_BACKFILL_WORKERS = 10

      attr_reader :user

      def page_title
        "#{user.login} - Search"
      end

      def search_record
        return @search_record if defined? @search_record

        index = Elastomer::Indexes::Users.primary
        result = index.docs.get(type: "user", id: user.id)

        @search_record =
            if result["found"]
              source = result["_source"]
              source["_id"] = result["_id"]
              source
            end
      rescue ElastomerClient::Client::Error => e
        Failbot.report e
        @search_record = nil
      end

      def search_record_exists?
        !search_record.nil?
      end

      def is_organization?
        search_record_exists? && search_record["organization"]
      end

      def each_entry(&block)
        sr = search_record
        sr.keys.sort.each { |key| block.call(key, sr[key]) }
        self
      end

      # Returns the list of in-progress backfill jobs for this organization,
      # along with their current status. Each entry is a Hash with:
      #
      #   :key      - the backfill type key (e.g. "pull_request")
      #   :label    - the display label for the backfill type
      #   :job      - the underlying Elastomer::RepairJob instance
      #   :paused   - Boolean, true if the job is paused
      #   :active   - Boolean, true if the job is currently active
      #   :finished - Boolean, true if the job has finished
      #   :workers  - the requested worker count
      #   :working  - the number of workers currently processing
      #   :progress - the percent complete (0.0 - 100.0)
      def backfill_jobs
        return [] unless is_organization?

        ::Stafftools::Users::SearchRecords::BackfillJob::BACKFILL_TYPES.filter_map do |key, config|
          job = config[:job_class].new(
            config[:index],
            upsert_only: true,
            purge: false,
            target_scope: :organization,
            target_scope_id: user.id,
          )
          next unless safe_job_exists?(job)

          {
            key: key,
            label: config[:label],
            job: job,
            paused: job.paused?,
            active: job.active?,
            finished: job.finished?,
            workers: job.workers,
            working: job.working,
            progress: job.progress,
          }
        rescue => e
          Failbot.report(e)
          nil
        end
      end

      private

      def safe_job_exists?(job)
        job.exists?
      rescue => e
        Failbot.report(e)
        false
      end
    end
  end
end
