# typed: true
# frozen_string_literal: true
module GitHub
  module Connect
    class ActionsJobExecutionExporter < Authenticator
      include GitHub::Memoizer

      MAX_BATCH_SIZE = 10000.freeze

      attr_reader :num_batches, :start_date, :end_date, :cancelled

      def initialize(batch_size: MAX_BATCH_SIZE, start_date: 24.hours.ago.utc, end_date: Time.now.utc)
        if start_date > end_date
          raise ArgumentError.new("start_date must be before end_date")
        end

        @start_date = start_date
        @end_date = end_date

        # export api is limited to 10k records per call
        @batch_size = batch_size > MAX_BATCH_SIZE || batch_size <= 0 ? MAX_BATCH_SIZE : batch_size
        @num_batches = (total_records / @batch_size.to_f).ceil
        @cancelled = false
      end

      # total_records returns the total number of records that will be exported based on @start_date and @end_date
      # Note: This function is mainly used for observability purposes. If this presents a performance concern we can
      # remove this and refactor the batching logic in the exporter to not require it.
      memoize def total_records
        return @export_total if defined?(@export_total)
        @export_total = GhesActionsJobExecution.created_between(@start_date, @end_date).count
        @export_total
      end

      # start exports events created between @start_date and @end_date
      # If cur_event_offset is zero the export will start with the earliest record
      def start
        return unless
          GitHub.enterprise? &&
          GitHub.ghe_usage_metrics_enabled? &&
          GitHub.environment.fetch("ENTERPRISE_ENABLE_ACTIONS_USAGE_STATS", false) == "true"

        now = Time.now.utc.iso8601
        server_id = DotcomConnection.new.server_id

        GitHub.logger.with_named_tags({
          "code.function": "ActionsJobExecutionExporter#start",
          "gh.batches": @num_batches,
          "gh.batch_size": @batch_size,
          "gh.total_records": total_records }) do
          GitHub.logger.info("starting export")

          offset = 0
          # Technically, the batching logic doesn't need @num_batches. We could loop until no more reocrds are returned
          # Structuring it this way makes it subjectively easier to log as well as refactor to run batches async later
          @num_batches.times do |i|
            GitHub.logger.with_named_tags({ "gh.batch": i + 1, "gh.offset": offset }) do
              GitHub.logger.info("starting batch")
              # pluck is used for performance reasons. Using select instantiates full ActiveRecord objects
              # which are not needed since we're the exporting data via API
              events = []

              begin
                events = GhesActionsJobExecution
                .created_between(@start_date, @end_date)
                .offset(offset)
                .limit(@batch_size)
                .pluck(
                  :invoking_event_type,
                  :workflow_repository_id,
                  :workflow_repository_global_id,
                  :workflow_repository_visibility,
                  :workflow_build_id,
                  :job_id,
                  :job_runtime,
                  :job_runtime_version,
                  :check_suite_id,
                  :check_run_id,
                  :start_time,
                  :end_time,
                  :job_execution_billable_ms,
                  :runner_properties,
                  :runner_type,
                  :job_check_run_conclusion,
                  :organization_id)
                .map do |r|
                  {
                    invoking_event_type: r[0],
                    workflow_repository_id: r[1],
                    workflow_repository_global_id: r[2],
                    workflow_repository_visibility: r[3],
                    workflow_build_id: r[4],
                    job_id: r[5],
                    job_runtime: r[6],
                    job_runtime_version: r[7],
                    check_suite_id: r[8],
                    check_run_id: r[9],
                    start_time: r[10].iso8601,
                    end_time: r[11].iso8601,
                    job_execution_billable_ms: r[12],
                    runner_properties: r[13],
                    runner_type: r[14],
                    job_check_run_conclusion: r[15],
                    organization_id: r[16]
                  }
                end
              rescue ActiveRecord::ActiveRecordError => e
                GitHub.logger.error({
                  exception: e,
                  message: "Error getting records to export, skipping batch",
                })

                next
              end

              if events.empty?
                GitHub.logger.info("no events found, stopping export")
                return
              end

              offset += @batch_size

              body = {
                server_id: server_id,
                collected_at: now,
                job_executions: events
              }

              GitHub.logger.info("exporting batch")
              response = GitHub::Connect.github_app_authenticated do
                begin
                  enterprise_installation_api("/enterprise-installation/usage-metrics/actions-job-executions",
                  body.to_json,
                  GitHub::Connect.auth_headers,
                  :post)
                rescue GitHub::Connect::Authenticator::ConnectionError => ce
                  # a Connection being raised indicates a transient error or a timeout so move on to the next batch
                  GitHub.logger.error("Connection error exporting while exporting batch, skipping", ce)
                rescue GitHub::Connect::Authenticator::AuthenticationError => ae
                  # this error is raised on a 403 status. This could mean that either there is an authentication issue
                  # or the call was rate-limited. In either case stop processing immediately
                  GitHub.logger.error("Authentication error or rate-limit in batch. Cancelling export", ae)

                  @cancelled = true
                  return
                end
              end

              GitHub.logger.info("batch completed")
            end
          end
        end
      end
    end
  end
end
